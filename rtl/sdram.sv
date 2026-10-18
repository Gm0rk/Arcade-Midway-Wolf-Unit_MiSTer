//============================================================================
//  SDRAM controller, 4 burst-read channels (one also writes) + 1 word write
//  channel
//
//  Adapted from Sorgelig's multi-channel MiSTer controller (GPL-3.0, itself
//  using parts of hamsterworks' Simple SDRAM Controller). The pin timing is
//  kept exactly as in that proven design: SDRAM_CLK is clk inverted through an
//  altddio_out, CAS latency 3, data captured through a register stage, one
//  access at a time with auto-precharge.
//
//  Changes for these cores: four read channels returning a 64-bit line
//  (burst of 4 words, line address aligned to 8 bytes), one 16-bit write
//  channel with byte enables, and a level req/ack handshake (req toggles to
//  request, ack follows req when done) so clients can queue back-to-back
//  requests.
//
//  Wolf Unit: channel 1 (the TMS34010) can also write one 16-bit word
//  (ch1_we, with byte enables), because the board's 512 KB main RAM lives in
//  SDRAM. Its writes go out at channel 1's priority, so a burst of blitter
//  reads cannot hold the CPU up the way the low-priority download channel
//  would. A write is acknowledged once the WRITE command has gone out; the
//  next access to the same bank opens its row afterwards, so a read that
//  follows it on any channel sees the new data. After a write the next
//  command waits out the write recovery and the auto precharge (the
//  original waited 2 clocks less, under tRC at 96 MHz).
//
//  Channel priority is fixed: ch0 > ch1 > ch2 > ch3 > write.
//
//  Copyright (C) 2015-2019 Sorgelig, 2026 Gm0rk - GPL-3.0-or-later
//============================================================================

module sdram
(
	input             init,        // reset to initialise the SDRAM
	input             clk,         // 96 MHz

`ifdef SDRAM_SIM
	// simulation: the bidirectional bus split into its two directions
	input      [15:0] SDRAM_DQ_I,
	output     [15:0] SDRAM_DQ_O,
	output            SDRAM_DQ_OE,
`else
	inout      [15:0] SDRAM_DQ,
`endif
	output reg [12:0] SDRAM_A,
	output            SDRAM_DQML,
	output            SDRAM_DQMH,
	output reg  [1:0] SDRAM_BA,
	output            SDRAM_nCS,
	output            SDRAM_nWE,
	output            SDRAM_nRAS,
	output            SDRAM_nCAS,
	output            SDRAM_CKE,
	output            SDRAM_CLK,

	// read channels: toggle req, wait for ack == req, line valid in dout
	input      [24:3] ch0_addr,    // byte address of an 8-byte line (32 MB)
	input             ch0_req,
	output reg        ch0_ack,
	output reg [63:0] ch0_dout,

	input      [24:1] ch1_addr,    // reads use [24:3]; a write writes the word at [24:1]
	input             ch1_req,
	output reg        ch1_ack,
	output reg [63:0] ch1_dout,
	input             ch1_we,      // this request is a one-word write
	input      [15:0] ch1_din,
	input       [1:0] ch1_be,

	input      [24:3] ch2_addr,
	input             ch2_req,
	output reg        ch2_ack,
	output reg [63:0] ch2_dout,

	input      [24:3] ch3_addr,
	input             ch3_req,
	output reg        ch3_ack,
	output reg [63:0] ch3_dout,

	// write channel: one 16-bit word
	input      [24:1] wr_addr,
	input      [15:0] wr_data,
	input       [1:0] wr_be,
	input             wr_req,
	output reg        wr_ack
);

assign SDRAM_nCS  = 1'b0;
assign SDRAM_nRAS = command[2];
assign SDRAM_nCAS = command[1];
assign SDRAM_nWE  = command[0];
assign SDRAM_CKE  = 1'b1;
assign {SDRAM_DQMH, SDRAM_DQML} = SDRAM_A[12:11];

localparam BURST_LENGTH   = 4;
localparam BURST_CODE     = 3'b010;
localparam ACCESS_TYPE    = 1'b0;    // sequential
localparam CAS_LATENCY    = 3'd3;
localparam OP_MODE        = 2'b00;
localparam NO_WRITE_BURST = 1'b1;    // reads burst, writes are single words
localparam MODE           = {3'b000, NO_WRITE_BURST, OP_MODE, CAS_LATENCY, ACCESS_TYPE, BURST_CODE};

localparam STARTUP_CYCLES = 14'd12100;  // 100 us plus margin
localparam REFRESH_CYCLES = 14'd740;    // 64 ms / 8192 rows at 96 MHz
localparam STARTUP_MAX    = 14'h3FFF;

localparam [2:0] CMD_NOP          = 3'b111;
localparam [2:0] CMD_ACTIVE       = 3'b011;
localparam [2:0] CMD_READ         = 3'b101;
localparam [2:0] CMD_WRITE        = 3'b100;
localparam [2:0] CMD_PRECHARGE    = 3'b010;
localparam [2:0] CMD_AUTO_REFRESH = 3'b001;
localparam [2:0] CMD_LOAD_MODE    = 3'b000;

localparam STATE_STARTUP = 4'd0;
localparam STATE_WAIT    = 4'd1;
localparam STATE_RW1     = 4'd2;
localparam STATE_IDLE    = 4'd4;
localparam STATE_IDLE_1  = 4'd5;
localparam STATE_IDLE_2  = 4'd6;
localparam STATE_IDLE_3  = 4'd7;
localparam STATE_IDLE_4  = 4'd8;
localparam STATE_IDLE_5  = 4'd9;
localparam STATE_RFSH    = 4'd10;

reg [13:0] refresh_count = STARTUP_MAX - STARTUP_CYCLES;
reg  [2:0] command;
reg  [3:0] state = STATE_STARTUP;

// read data pipeline: one shift register marks when each burst word arrives
localparam DLY = CAS_LATENCY + BURST_LENGTH + 1;
reg  [DLY:0] rd_delay;
reg    [1:0] rd_ch;          // channel of the read in flight
reg   [15:0] dq_reg;
reg   [63:0] rd_line;

reg          saved_wr;
reg   [12:0] cas_addr;
reg   [15:0] dq_out;
reg          dq_oe;

`ifdef SDRAM_SIM
assign SDRAM_DQ_O  = dq_out;
assign SDRAM_DQ_OE = dq_oe;
wire  [15:0] dq_in = SDRAM_DQ_I;
`else
assign SDRAM_DQ    = dq_oe ? dq_out : 16'bZ;
wire  [15:0] dq_in = SDRAM_DQ;
`endif
reg   [15:0] saved_data;
reg    [2:0] cur;            // 0-3 read channel, 4 write

// The IDLE state's checks, from registers: rd_busy[n] is "a read for channel
// n is still coming in" (rd_delay != 0 && rd_ch == n) and rfsh_due "a
// refresh is due" (refresh_count > REFRESH_CYCLES), each worked out a clock
// ahead from the values these registers take next, so the choice of the next
// access starts from flip-flops instead of the read pipeline and the count.
wire           rd_issue = (state == STATE_RW1) && !saved_wr;
wire   [DLY:0] rd_dly_nx = init ? {(DLY + 1){1'b0}} : ((rd_delay >> 1) | (rd_issue ? {1'b1, {DLY{1'b0}}} : {(DLY + 1){1'b0}}));
wire     [1:0] rd_ch_nx  = rd_issue ? cur[1:0] : rd_ch;
reg      [3:0] rd_busy = 4'd0;
reg            rfsh_due = 1'b0;
reg     [13:0] rc_nx;
always @(*) begin
	rc_nx = refresh_count + 1'b1;
	if (state == STATE_STARTUP && refresh_count == 14'd0) rc_nx = 14'd0;
	if (state == STATE_IDLE && rfsh_due)                  rc_nx = refresh_count - REFRESH_CYCLES + 1'd1;
	if (init)                                             rc_nx = STARTUP_MAX - STARTUP_CYCLES;
end

always @(posedge clk) begin
	rd_busy[0] <= (rd_dly_nx != 0) && (rd_ch_nx == 2'd0);
	rd_busy[1] <= (rd_dly_nx != 0) && (rd_ch_nx == 2'd1);
	rd_busy[2] <= (rd_dly_nx != 0) && (rd_ch_nx == 2'd2);
	rd_busy[3] <= (rd_dly_nx != 0) && (rd_ch_nx == 2'd3);
	rfsh_due   <= rc_nx > REFRESH_CYCLES;
end

always @(posedge clk) begin
	refresh_count <= refresh_count + 1'b1;
	rd_delay      <= rd_delay >> 1;
	dq_reg        <= dq_in;

	// assemble the four burst words of a line, then hand it to its channel
	if (rd_delay[4]) rd_line[15:0]  <= dq_reg;
	if (rd_delay[3]) rd_line[31:16] <= dq_reg;
	if (rd_delay[2]) rd_line[47:32] <= dq_reg;
	if (rd_delay[1]) begin
		case (rd_ch)
			2'd0: begin ch0_dout <= {dq_reg, rd_line[47:0]}; ch0_ack <= ch0_req; end
			2'd1: begin ch1_dout <= {dq_reg, rd_line[47:0]}; ch1_ack <= ch1_req; end
			2'd2: begin ch2_dout <= {dq_reg, rd_line[47:0]}; ch2_ack <= ch2_req; end
			default: begin ch3_dout <= {dq_reg, rd_line[47:0]}; ch3_ack <= ch3_req; end
		endcase
	end

	dq_oe    <= 1'b0;
	command  <= CMD_NOP;

	case (state)
		STATE_STARTUP: begin
			SDRAM_A  <= 13'd0;
			SDRAM_BA <= 2'd0;
			if (refresh_count == (STARTUP_MAX - 63) || refresh_count == (STARTUP_MAX - 31)) begin
				command     <= CMD_PRECHARGE;
				SDRAM_A[10] <= 1'b1;    // all banks
			end
			if (refresh_count == (STARTUP_MAX - 55) || refresh_count == (STARTUP_MAX - 23) ||
			    refresh_count == (STARTUP_MAX - 47) || refresh_count == (STARTUP_MAX - 15))
				command <= CMD_AUTO_REFRESH;
			if (refresh_count == (STARTUP_MAX - 39) || refresh_count == (STARTUP_MAX - 7)) begin
				command <= CMD_LOAD_MODE;
				SDRAM_A <= MODE;
			end
			if (refresh_count == 14'd0) begin
				state         <= STATE_IDLE;
				refresh_count <= 14'd0;
			end
		end

		STATE_IDLE_5: state <= STATE_IDLE_4;
		STATE_IDLE_4: state <= STATE_IDLE_3;
		STATE_IDLE_3: state <= STATE_IDLE_2;
		STATE_IDLE_2: state <= STATE_IDLE_1;
		STATE_IDLE_1: state <= STATE_IDLE;

		STATE_RFSH: state <= STATE_IDLE_5;

		STATE_IDLE: begin
			// word address split: bank = [24:23], row = [22:10], column = [9:1]
			// (32 MB module); cas_addr carries DQM in [12:11], auto-precharge in [10]
			if (rfsh_due) begin
				state         <= STATE_RFSH;
				command       <= CMD_AUTO_REFRESH;
				refresh_count <= refresh_count - REFRESH_CYCLES + 1'd1;
			end
			else if (ch0_req != ch0_ack && !rd_busy[0]) begin
				{cas_addr[12:9], SDRAM_BA, SDRAM_A, cas_addr[8:0]} <= {2'b00, 1'b1, 1'b0, ch0_addr, 2'b00};
				saved_wr <= 1'b0;
				cur      <= 3'd0;
				command  <= CMD_ACTIVE;
				state    <= STATE_WAIT;
			end
			else if (ch1_req != ch1_ack && !rd_busy[1]) begin
				if (ch1_we) begin
					{cas_addr[12:9], SDRAM_BA, SDRAM_A, cas_addr[8:0]} <= {~ch1_be, 1'b1, 1'b0, ch1_addr};
					saved_data <= ch1_din;
					saved_wr   <= 1'b1;
				end
				else begin
					{cas_addr[12:9], SDRAM_BA, SDRAM_A, cas_addr[8:0]} <= {2'b00, 1'b1, 1'b0, ch1_addr[24:3], 2'b00};
					saved_wr   <= 1'b0;
				end
				cur      <= 3'd1;
				command  <= CMD_ACTIVE;
				state    <= STATE_WAIT;
			end
			else if (ch2_req != ch2_ack && !rd_busy[2]) begin
				{cas_addr[12:9], SDRAM_BA, SDRAM_A, cas_addr[8:0]} <= {2'b00, 1'b1, 1'b0, ch2_addr, 2'b00};
				saved_wr <= 1'b0;
				cur      <= 3'd2;
				command  <= CMD_ACTIVE;
				state    <= STATE_WAIT;
			end
			else if (ch3_req != ch3_ack && !rd_busy[3]) begin
				{cas_addr[12:9], SDRAM_BA, SDRAM_A, cas_addr[8:0]} <= {2'b00, 1'b1, 1'b0, ch3_addr, 2'b00};
				saved_wr <= 1'b0;
				cur      <= 3'd3;
				command  <= CMD_ACTIVE;
				state    <= STATE_WAIT;
			end
			else if (wr_req != wr_ack) begin
				{cas_addr[12:9], SDRAM_BA, SDRAM_A, cas_addr[8:0]} <= {~wr_be, 1'b1, 1'b0, wr_addr};
				saved_data <= wr_data;
				saved_wr   <= 1'b1;
				cur        <= 3'd4;
				command    <= CMD_ACTIVE;
				state      <= STATE_WAIT;
			end
		end

		STATE_WAIT: state <= STATE_RW1;

		STATE_RW1: begin
			SDRAM_A <= cas_addr;
			if (saved_wr) begin
				command  <= CMD_WRITE;
				dq_out   <= saved_data;
				dq_oe    <= 1'b1;
				if (cur == 3'd1) ch1_ack <= ch1_req;
				else             wr_ack  <= wr_req;
				// write recovery and the auto precharge before the next
				// ACTIVE or refresh: 7 clocks ACTIVE to ACTIVE (73 ns >= tRC
				// 60/63 ns), 5 from the WRITE (52 ns >= tDAL = tWR + tRP,
				// 30/35 ns) for -6/-7 parts
				state    <= STATE_IDLE_4;
			end
			else begin
				command <= CMD_READ;
				rd_ch   <= cur[1:0];
				rd_delay[DLY] <= 1'b1;
				state   <= STATE_IDLE_5;
			end
		end

		default: state <= STATE_IDLE;
	endcase

	if (init) begin
		state         <= STATE_STARTUP;
		refresh_count <= STARTUP_MAX - STARTUP_CYCLES;
		rd_delay      <= 0;
	end
end

`ifdef SDRAM_SIM
assign SDRAM_CLK = ~clk;
`else
altddio_out
#(
	.extend_oe_disable("OFF"),
	.intended_device_family("Cyclone V"),
	.invert_output("OFF"),
	.lpm_hint("UNUSED"),
	.lpm_type("altddio_out"),
	.oe_reg("UNREGISTERED"),
	.power_up_high("OFF"),
	.width(1)
)
sdramclk_ddr
(
	.datain_h(1'b0),
	.datain_l(1'b1),
	.outclock(clk),
	.dataout(SDRAM_CLK),
	.aclr(1'b0),
	.aset(1'b0),
	.oe(1'b1),
	.outclocken(1'b1),
	.sclr(1'b0),
	.sset(1'b0)
);
`endif

endmodule
