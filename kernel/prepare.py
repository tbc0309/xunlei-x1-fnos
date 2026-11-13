#!/usr/bin/env python3
"""Stage the recovered X1 changes against the matching Linux stable tag."""
import shutil
import sys
from pathlib import Path

here = Path(__file__).resolve().parent
abi, linux, output = sys.argv[1:]
if abi not in ('6.12.41-trim', '6.18.18.c1202-trim'):
    raise SystemExit(f'Unsupported ABI: {abi}')
old = abi.startswith('6.12.')
drm = Path(linux) / 'drivers/gpu/drm'
output = Path(output)
shutil.copytree(drm / 'rockchip', output / 'rockchip')
for directory in ('bridge', 'panel'):
    (output / directory).mkdir()


def insert(source, marker, content):
    if source.count(marker) != 1:
        raise ValueError(f'Expected one source marker: {marker}')
    return source.replace(marker, content + marker, 1)


host = output / 'rockchip/dw-mipi-dsi-rockchip.c'
s = host.read_text()
if old:
    s = insert(s, 'static int\ndw_mipi_dsi_get_lane_mbps(', '''static uint lshz_lane_mbps;
module_param(lshz_lane_mbps, uint, 0444);
MODULE_PARM_DESC(lshz_lane_mbps, "Override DSI0 lane rate in Mbps on lshz,rk3399");

''')
    rate = '''	if (lshz_lane_mbps && of_machine_is_compatible("lshz,rk3399")) {
		if (lshz_lane_mbps < 80 || lshz_lane_mbps > max_mbps)
			return -EINVAL;
		target_mbps = lshz_lane_mbps;
	}

'''
    key = 'dsi->feedback_div = best_fbdiv;'
    s = s.replace(key, key + '''
		dev_info(dsi->dev, "LSHZ D-PHY target %u, actual %u Mbps/lane\\n",
			 target_mbps, dsi->lane_mbps);''')
else:
    rate = '''	if (of_machine_is_compatible("lshz,rk3399") &&
	    !strcmp(dev_name(dsi->dev), "ff960000.dsi") && lanes == 4 &&
	    mode->clock == 20000 && mode->hdisplay == 640 && mode->vdisplay == 480)
		target_mbps = 252;
'''
host.write_text(insert(s, '	fin = clk_get_rate(dsi->pllref_clk);', rate))

s = (drm / 'bridge/synopsys/dw-mipi-dsi.c').read_text()
if '#include <linux/of.h>' not in s:
    s = insert(s, '#include <linux/module.h>', '#include <linux/of.h>\n')
scope = '''of_machine_is_compatible("lshz,rk3399") &&
	    !strcmp(dev_name(dsi->dev), "ff960000.dsi") &&
	    dsi->lanes == 4 && dsi->lane_mbps == 252'''
s = insert(s, '	frac = lbcc % mode->clock;', f'''	if ({scope} &&
	    mode->clock == 20000 && mode->hdisplay == 640 && mode->vdisplay == 480 &&
	    (dsi->mode_flags & MIPI_DSI_MODE_VIDEO_BURST))
		return DIV_ROUND_CLOSEST(lbcc, mode->clock);

''')
s = insert(s, '	hw_version = dsi_read(dsi, DSI_VERSION) & VERSION;', f'''	if ({scope}) {{
		timing.clk_hs2lp = 0x40;
		timing.clk_lp2hs = 0x40;
		timing.data_hs2lp = 0x14;
		timing.data_lp2hs = 0x10;
	}}

''')
(output / 'bridge/dw-mipi-dsi.c').write_text(s)
(output / 'bridge/Kbuild').write_text('obj-m := dw-mipi-dsi.o\n')
for file in ('panel-rk3399-640x480.c', 'panel-rk3399-640x480-init.h'):
    shutil.copyfile(here / file, output / 'panel' / file)
(output / 'panel/Kbuild').write_text('obj-m := panel-rk3399-640x480.o\n')
