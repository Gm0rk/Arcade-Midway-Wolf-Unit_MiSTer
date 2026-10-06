// mame_dma.h - reference model of the T-Unit / Wolf Unit blitter
//
// MAME 0.289's midtunit_video_device::dma_w and dma_draw (midtunit_v.cpp,
// license BSD-3-Clause, copyright-holders Alex Pasadyn, Zsolt Vasvari,
// Ernesto Corvi, Aaron Giles), with the template parameters turned into
// run-time arguments and nothing else changed, for comparison with
// rtl/wunit_dma.sv. gfx_rom_large is set, as on the Wolf Unit.

#pragma once
#include <cstdint>
#include <cstring>

struct MameDma
{
	enum op_type_t { PIXEL_SKIP = 0, PIXEL_COLOR = 1, PIXEL_COPY = 2 };
	enum { DMA_LRSKIP = 0, DMA_COMMAND, DMA_OFFSETLO, DMA_OFFSETHI, DMA_XSTART, DMA_YSTART,
	       DMA_WIDTH, DMA_HEIGHT, DMA_PALETTE, DMA_COLOR, DMA_SCALE_X, DMA_SCALE_Y,
	       DMA_TOPCLIP, DMA_BOTCLIP, DMA_UNKNOWN_E, DMA_CONFIG, DMA_LEFTCLIP, DMA_RIGHTCLIP };
	static constexpr uint32_t XPOSMASK = 0x3ff;
	static constexpr uint32_t YPOSMASK = 0x1ff;

	struct dma_state {
		const uint8_t *gfxrom;
		uint32_t offset; int32_t rowbits, xpos, ypos, width, height;
		uint16_t palette, color;
		uint8_t yflip, preskip, postskip;
		int32_t topclip, botclip, leftclip, rightclip, startskip, endskip;
		uint16_t xstep, ystep;
	} m_dma_state;

	uint16_t m_dma_register[18] = {};
	uint16_t *m_local_videoram;            // 0x80000 entries
	bool irq = false;
	int last_pixels = 0;                   // pixels the completion timer was set for

	uint32_t extract(const uint8_t *base, uint32_t o, int m)
	{
		return (((base[o >> 3] | (base[(o >> 3) + 1] << 8)) >> (o & 7)) & (m));
	}

	void dma_draw(int BitsPerPixel, bool XFlip, bool Skip, bool Scale, op_type_t Zero, op_type_t NonZero)
	{
		int const height = m_dma_state.height << 8;
		uint8_t const *const base = m_dma_state.gfxrom;
		uint32_t offset = m_dma_state.offset;
		uint16_t pal = m_dma_state.palette;
		uint16_t color = pal | m_dma_state.color;
		int sy = m_dma_state.ypos;
		int iy = 0;
		int ty;
		int const mask = (1 << BitsPerPixel) - 1;
		int const xstep = Scale ? m_dma_state.xstep : 0x100;

		while (iy < height)
		{
			int const startskip = m_dma_state.startskip << 8;
			int endskip = m_dma_state.endskip << 8;
			int width = m_dma_state.width << 8;
			int sx = m_dma_state.xpos;
			int ix = 0;
			int tx;
			uint32_t o = offset;
			int pre = 0, post = 0;
			uint16_t *d;

			if (Skip)
			{
				uint8_t const value = extract(base, o, 0xff);
				o += 8;
				pre = (value & 0x0f) << (m_dma_state.preskip + 8);
				tx = pre / xstep;
				if (XFlip)
					sx = (sx - tx) & XPOSMASK;
				else
					sx = (sx + tx) & XPOSMASK;
				ix += tx * xstep;
				post = ((value >> 4) & 0x0f) << (m_dma_state.postskip + 8);
				width -= post;
				endskip -= post;
			}
			(void)endskip;

			if (sy < m_dma_state.topclip || sy > m_dma_state.botclip)
				goto clipy;

			if (ix < startskip)
			{
				tx = ((startskip - ix) / xstep) * xstep;
				ix += tx;
				o += (tx >> 8) * BitsPerPixel;
			}

			if ((width >> 8) > m_dma_state.width - m_dma_state.endskip)
				width = (m_dma_state.width - m_dma_state.endskip) << 8;

			d = &m_local_videoram[sy * 512];

			while (ix < width)
			{
				if (sx >= m_dma_state.leftclip && sx <= m_dma_state.rightclip)
				{
					if (Zero == NonZero)
					{
						if (Zero == PIXEL_COLOR)
							d[sx] = color;
						else if (Zero == PIXEL_COPY)
							d[sx] = (extract(base, o, mask)) | pal;
					}
					else
					{
						int pixel = (extract(base, o, mask));
						if (pixel)
						{
							if (NonZero == PIXEL_COLOR)
								d[sx] = color;
							else if (NonZero == PIXEL_COPY)
								d[sx] = pixel | pal;
						}
						else
						{
							if (Zero == PIXEL_COLOR)
								d[sx] = color;
							else if (Zero == PIXEL_COPY)
								d[sx] = pal;
						}
					}
				}

				if (XFlip)
					sx = (sx - 1) & XPOSMASK;
				else
					sx = (sx + 1) & XPOSMASK;

				if (!Scale)
				{
					ix += 0x100;
					o += BitsPerPixel;
				}
				else
				{
					tx = ix >> 8;
					ix += xstep;
					tx = (ix >> 8) - tx;
					o += BitsPerPixel * tx;
				}
			}

		clipy:
			if (m_dma_state.yflip)
				sy = (sy - 1) & YPOSMASK;
			else
				sy = (sy + 1) & YPOSMASK;
			if (!Scale)
			{
				iy += 0x100;
				width = m_dma_state.width;
				if (Skip)
				{
					offset += 8;
					width -= (pre + post) >> 8;
					if (width > 0) offset += width * BitsPerPixel;
				}
				else
				{
					offset += width * BitsPerPixel;
				}
			}
			else
			{
				ty = iy >> 8;
				iy += m_dma_state.ystep;
				ty = (iy >> 8) - ty;
				if (!Skip)
				{
					offset += ty * m_dma_state.width * BitsPerPixel;
				}
				else if (ty--)
				{
					o = offset + 8;
					width = m_dma_state.width - ((pre + post) >> 8);
					if (width > 0) o += width * BitsPerPixel;
					while (ty--)
					{
						uint8_t const value = extract(base, o, 0xff);
						o += 8;
						pre = (value & 0x0f) << m_dma_state.preskip;
						post = ((value >> 4) & 0x0f) << m_dma_state.postskip;
						width = m_dma_state.width - pre - post;
						if (width > 0) o += width * BitsPerPixel;
					}
					offset = o;
				}
			}
		}
	}

	// the draw routine MAME's tables pick for (command & 0x1f)
	void draw_for(int command, int bpp, bool skip, bool scale)
	{
		int i = command & 0x1f;
		bool xf = i & 0x10;
		int op = i & 0x0f;
		op_type_t z, nz;
		switch (op)
		{
			case 0: return;                                         // none
			case 1: z = PIXEL_COPY;  nz = PIXEL_SKIP;  break;      // P0
			case 2: z = PIXEL_SKIP;  nz = PIXEL_COPY;  break;      // P1
			case 3: z = PIXEL_COPY;  nz = PIXEL_COPY;  break;      // P0P1
			case 4: case 5: z = PIXEL_COLOR; nz = PIXEL_SKIP; break;  // C0
			case 6: case 7: z = PIXEL_COLOR; nz = PIXEL_COPY; break;  // C0P1
			case 8: case 10: z = PIXEL_SKIP; nz = PIXEL_COLOR; break; // C1
			case 9: case 11: z = PIXEL_COPY; nz = PIXEL_COLOR; break; // P0C1
			default: z = PIXEL_COLOR; nz = PIXEL_COLOR; break;       // C0C1
		}
		dma_draw(bpp ? bpp : 8, xf, skip, scale, z, nz);
	}

	// returns true when a blit was started
	bool dma_w(int offset, uint16_t data)
	{
		static const uint8_t register_map[2][16] =
		{
			{ 0,1,2,3,4,5,6,7,8,9,10,11,16,17,14,15 },
			{ 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15 }
		};
		int const regbank = (m_dma_register[DMA_CONFIG] >> 5) & 1;
		int pixels = 0;

		int regnum = register_map[regbank][offset];
		m_dma_register[regnum] = data;

		if (regnum != DMA_COMMAND)
			return false;

		int const command = m_dma_register[DMA_COMMAND];
		irq = false;
		if (!(command & 0x8000))
			return false;

		int const bpp = (command >> 12) & 7;

		m_dma_state.xpos = m_dma_register[DMA_XSTART] & XPOSMASK;
		m_dma_state.ypos = m_dma_register[DMA_YSTART] & YPOSMASK;
		m_dma_state.width = m_dma_register[DMA_WIDTH] & 0x3ff;
		m_dma_state.height = m_dma_register[DMA_HEIGHT] & 0x3ff;
		m_dma_state.palette = m_dma_register[DMA_PALETTE] & 0x7f00;
		m_dma_state.color = m_dma_register[DMA_COLOR] & 0xff;

		m_dma_state.yflip = (command & 0x20) >> 5;
		m_dma_state.preskip = (command >> 8) & 3;
		m_dma_state.postskip = (command >> 10) & 3;
		m_dma_state.xstep = m_dma_register[DMA_SCALE_X] ? m_dma_register[DMA_SCALE_X] : 0x100;
		m_dma_state.ystep = m_dma_register[DMA_SCALE_Y] ? m_dma_register[DMA_SCALE_Y] : 0x100;

		m_dma_state.topclip = m_dma_register[DMA_TOPCLIP] & 0x1ff;
		m_dma_state.botclip = m_dma_register[DMA_BOTCLIP] & 0x1ff;
		m_dma_state.leftclip = m_dma_register[DMA_LEFTCLIP] & 0x3ff;
		m_dma_state.rightclip = m_dma_register[DMA_RIGHTCLIP] & 0x3ff;

		uint32_t gfxoffset = m_dma_register[DMA_OFFSETLO] | (m_dma_register[DMA_OFFSETHI] << 16);

		if ((command & 0x0f) == 0x0c)
			gfxoffset = 0;

		// gfx_rom_large: no 0x2000000 fold
		if (gfxoffset >= 0xf8000000)
			gfxoffset -= 0xf8000000;
		if (gfxoffset < 0x10000000)
			m_dma_state.offset = gfxoffset;
		else
			goto skipdma;

		if (command & 0x40)
		{
			m_dma_state.startskip = m_dma_register[DMA_LRSKIP] & 0xff;
			m_dma_state.endskip = m_dma_register[DMA_LRSKIP] >> 8;
		}
		else
		{
			m_dma_state.startskip = 0;
			m_dma_state.endskip = m_dma_register[DMA_LRSKIP];
		}

		if (m_dma_state.xstep == 0x100 && m_dma_state.ystep == 0x100)
		{
			draw_for(command, bpp, command & 0x80, false);
			pixels = m_dma_state.width * m_dma_state.height;
		}
		else
		{
			draw_for(command, bpp, command & 0x80, true);
			if (m_dma_state.xstep && m_dma_state.ystep)
				pixels = ((m_dma_state.width << 8) / m_dma_state.xstep) * ((m_dma_state.height << 8) / m_dma_state.ystep);
			else
				pixels = 0;
		}

	skipdma:
		last_pixels = pixels;
		return true;
	}
};
