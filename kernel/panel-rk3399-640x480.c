// SPDX-License-Identifier: GPL-2.0-only
#include <linux/delay.h>
#include <linux/gpio/consumer.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/regulator/consumer.h>
#include <linux/slab.h>

#include <drm/drm_connector.h>
#include <drm/drm_mipi_dsi.h>
#include <drm/drm_modes.h>
#include <drm/drm_panel.h>

struct rk3399_panel {
	struct drm_panel panel;
	struct mipi_dsi_device *dsi;
	struct regulator *supply;
	struct gpio_desc *enable;
	struct gpio_desc *reset;
};

struct panel_command {
	u8 payload[2];
	u8 delay_ms;
};

/* DCS short writes with a parameter, recovered from the factory DTB. */
static bool cmd_hs = true;
module_param(cmd_hs, bool, 0644);
MODULE_PARM_DESC(cmd_hs, "Send panel commands in high-speed mode");

static const struct panel_command init_commands[] = {
#include "panel-rk3399-640x480-init.h"
};

static void rk3399_panel_power_off(struct rk3399_panel *p)
{
	gpiod_set_value_cansleep(p->reset, 1);
	gpiod_set_value_cansleep(p->enable, 0);
	regulator_disable(p->supply);
	msleep(20);
}

static int rk3399_panel_prepare(struct drm_panel *panel)
{
	struct rk3399_panel *p = container_of(panel, struct rk3399_panel, panel);
	unsigned int i;
	unsigned long mode_flags;
	int ret;

	ret = regulator_enable(p->supply);
	if (ret)
		return ret;

	gpiod_set_value_cansleep(p->enable, 1);
	msleep(20);
	gpiod_set_value_cansleep(p->reset, 1);
	msleep(20);
	gpiod_set_value_cansleep(p->reset, 0);
	msleep(20);

	mode_flags = p->dsi->mode_flags;
	if (cmd_hs)
		p->dsi->mode_flags &= ~MIPI_DSI_MODE_LPM;

	for (i = 0; i < ARRAY_SIZE(init_commands); i++) {
		const struct panel_command *cmd = &init_commands[i];

		if (i == ARRAY_SIZE(init_commands) - 2)
			ret = mipi_dsi_dcs_exit_sleep_mode(p->dsi);
		else if (i == ARRAY_SIZE(init_commands) - 1)
			ret = mipi_dsi_dcs_set_display_on(p->dsi);
		else
			ret = mipi_dsi_dcs_write_buffer(p->dsi, cmd->payload,
						       sizeof(cmd->payload));
		if (ret < 0) {
			dev_err(panel->dev, "panel command %u (%02x %02x, %s) failed: %d\n",
				i, cmd->payload[0], cmd->payload[1],
				cmd_hs ? "HS" : "LP", ret);
			p->dsi->mode_flags = mode_flags;
			rk3399_panel_power_off(p);
			return ret;
		}
		if (cmd->delay_ms)
			msleep(cmd->delay_ms);
		else
			usleep_range(1500, 2500);
	}

	p->dsi->mode_flags = mode_flags;
	dev_info(panel->dev, "panel initialization complete (%s)\n", cmd_hs ? "HS" : "LP");
	{
		u8 power_mode;

		ret = mipi_dsi_dcs_get_power_mode(p->dsi, &power_mode);
		if (ret < 0)
			dev_info(panel->dev, "panel power-mode read unavailable: %d\n", ret);
		else
			dev_info(panel->dev, "panel power mode: 0x%02x\n", power_mode);
	}
	return 0;
}

static int rk3399_panel_enable(struct drm_panel *panel)
{
	msleep(20);
	return 0;
}

static int rk3399_panel_disable(struct drm_panel *panel)
{
	msleep(20);
	return 0;
}

static int rk3399_panel_unprepare(struct drm_panel *panel)
{
	struct rk3399_panel *p = container_of(panel, struct rk3399_panel, panel);
	unsigned long mode_flags = p->dsi->mode_flags;
	int ret;

	if (cmd_hs)
		p->dsi->mode_flags &= ~MIPI_DSI_MODE_LPM;

	ret = mipi_dsi_dcs_set_display_off(p->dsi);
	if (ret < 0)
		dev_warn(panel->dev, "display-off failed: %d\n", ret);
	ret = mipi_dsi_dcs_enter_sleep_mode(p->dsi);
	if (ret < 0)
		dev_warn(panel->dev, "sleep-in failed: %d\n", ret);
	p->dsi->mode_flags = mode_flags;
	rk3399_panel_power_off(p);
	return 0;
}

static const struct drm_display_mode rk3399_panel_mode = {
	.clock = 20000,
	.hdisplay = 640,
	.hsync_start = 660,
	.hsync_end = 662,
	.htotal = 682,
	.vdisplay = 480,
	.vsync_start = 492,
	.vsync_end = 494,
	.vtotal = 498,
	.flags = DRM_MODE_FLAG_NHSYNC | DRM_MODE_FLAG_NVSYNC,
	.type = DRM_MODE_TYPE_DRIVER | DRM_MODE_TYPE_PREFERRED,
};

static int rk3399_panel_get_modes(struct drm_panel *panel,
				struct drm_connector *connector)
{
	struct drm_display_mode *mode;

	mode = drm_mode_duplicate(connector->dev, &rk3399_panel_mode);
	if (!mode)
		return -ENOMEM;
	drm_mode_set_name(mode);
	drm_mode_probed_add(connector, mode);
	connector->display_info.width_mm = 68;
	connector->display_info.height_mm = 121;
	connector->display_info.bpc = 8;

	return 1;
}

static const struct drm_panel_funcs rk3399_panel_funcs = {
	.prepare = rk3399_panel_prepare,
	.enable = rk3399_panel_enable,
	.disable = rk3399_panel_disable,
	.unprepare = rk3399_panel_unprepare,
	.get_modes = rk3399_panel_get_modes,
};

static int rk3399_panel_probe(struct mipi_dsi_device *dsi)
{
	struct device *dev = &dsi->dev;
	struct rk3399_panel *p;
	int ret;

	p = devm_kzalloc(dev, sizeof(*p), GFP_KERNEL);
	if (!p)
		return -ENOMEM;
	drm_panel_init(&p->panel, dev, &rk3399_panel_funcs,
		       DRM_MODE_CONNECTOR_DSI);
	p->dsi = dsi;

	p->supply = devm_regulator_get(dev, "power");
	if (IS_ERR(p->supply))
		return dev_err_probe(dev, PTR_ERR(p->supply), "panel supply\n");
	p->enable = devm_gpiod_get(dev, "enable", GPIOD_OUT_LOW);
	if (IS_ERR(p->enable))
		return dev_err_probe(dev, PTR_ERR(p->enable), "panel enable GPIO\n");
	p->reset = devm_gpiod_get(dev, "reset", GPIOD_OUT_HIGH);
	if (IS_ERR(p->reset))
		return dev_err_probe(dev, PTR_ERR(p->reset), "panel reset GPIO\n");

	ret = drm_panel_of_backlight(&p->panel);
	if (ret)
		return dev_err_probe(dev, ret, "panel backlight\n");

	p->panel.prepare_prev_first = true;
	dsi->lanes = 4;
	dsi->format = MIPI_DSI_FMT_RGB888;
	dsi->mode_flags = MIPI_DSI_MODE_VIDEO | MIPI_DSI_MODE_VIDEO_BURST |
			  MIPI_DSI_MODE_LPM;
	mipi_dsi_set_drvdata(dsi, p);
	drm_panel_add(&p->panel);
	ret = mipi_dsi_attach(dsi);
	if (ret)
		drm_panel_remove(&p->panel);
	return ret;
}

static void rk3399_panel_remove(struct mipi_dsi_device *dsi)
{
	struct rk3399_panel *p = mipi_dsi_get_drvdata(dsi);

	mipi_dsi_detach(dsi);
	drm_panel_remove(&p->panel);
}

static const struct of_device_id rk3399_panel_of_match[] = {
	{ .compatible = "lshz,rk3399-dsi-panel" },
	{ }
};
MODULE_DEVICE_TABLE(of, rk3399_panel_of_match);

static struct mipi_dsi_driver rk3399_panel_driver = {
	.probe = rk3399_panel_probe,
	.remove = rk3399_panel_remove,
	.driver = {
		.name = "panel-rk3399-640x480",
		.of_match_table = rk3399_panel_of_match,
	},
};
module_mipi_dsi_driver(rk3399_panel_driver);

MODULE_DESCRIPTION("LSHZ RK3399 640x480 MIPI DSI panel");
MODULE_LICENSE("GPL");
