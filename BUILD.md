# 构建与维护

本仓库维护迅雷盒子 X1 的板级用户态源码、内核驱动改动、DEB 安装脚本、6.18 initramfs 钩子和线刷打包流程。重打包使用对应版本的固件及 DEB 作为基线。

## 从源码编译显示模块

每个内核版本构建三个模块：`dw-mipi-dsi.ko`、`rockchipdrm.ko` 和 `panel-rk3399-640x480.ko`。面板驱动和初始化表在 `kernel/`。DRM 和 DSI 的改动从历史构建记录恢复，由 `prepare.py` 应用到 Linux stable。上游基线分别为 [v6.12.41](https://github.com/gregkh/linux/tree/v6.12.41) 和 [v6.18.18](https://github.com/gregkh/linux/tree/v6.18.18)。

在 ARM64 Linux 上准备 Bash、Python 3、GCC 12、make、binutils、kmod，以及来自对应飞牛内核的头文件、生成配置和 `Module.symvers`。飞牛上的头文件通常由 `/lib/modules/<ABI>/build` 指向。下载并解压两个对应的 Linux stable 源码树，再从仓库根目录运行：

```bash
bash kernel/build.sh 6.12.41-trim /path/to/linux-6.12.41 \
  /lib/modules/6.12.41-trim/build ./out-612
bash kernel/build.sh 6.18.18.c1202-trim /path/to/linux-6.18.18 \
  /lib/modules/6.18.18.c1202-trim/build ./out-618
```

输出目录必须是新目录。脚本检查头文件声明的内核版本和各模块的 vermagic，输出 SHA-256。交叉编译时可设置 `CROSS_COMPILE` 和 `CC`，并使用构建主机能够执行的内核构建工具。原发布版的模块包含不同的剥离与调试信息，SHA-256 主要用于标记本次构建的产物。

恢复验证在 X1 的 ARM64 环境使用 GCC 12.2 完成。两个 ABI 的三个模块均通过 Kbuild、MODPOST 和 vermagic 检查。与 beta3-fix1 对比，五个模块的 `.text` 一致，6.12 的 `rockchipdrm` 有机器码差异。6.18 因头文件包未提供 `vmlinux` 而跳过了 BTF 生成。这次新编译的模块尚未上板加载验证。

移植到新内核时，先将 `prepare.py` 的板级改动迁移到匹配的上游基线，再使用该飞牛 ABI 的配置和符号表构建。检查 initramfs 钩子的 ABI 限定和 depmod 规则，确认启动镜像选中三份板级模块，并在设备上验证冷启动、面板回读和实体屏刷新。

## 重建 DEB

在 Linux 或 WSL 安装 `dpkg-dev` 和 `kmod`。下载 Release 的 DEB 后执行：

```bash
bash build-deb.sh ./lshz-3399-dsi-timing_0.2.beta3+fix1_arm64.deb ./rebuilt.deb
```

脚本解包参考 DEB，覆盖 `src/` 中对应的可维护文件，检查六个模块的 vermagic，重建校验清单并打包。发布更新时同时更新 DEB 版本，避免包管理器把新版识别成同一版本。

要把本次源码编译的模块装入 DEB，在命令末尾追加两个构建目录：`./out-612 ./out-618`。打包时会检查每个模块的 ABI。

## 重建线刷包

1. 用 RKImageMaker 解包已有线刷 IMG，取得 `boot.bin` 和 `firmware.img`。再用 AFPTool 解开 `firmware.img`，取得清单、GPT 参数、U-Boot、Trust、boot 与 rootfs。
2. 用 `simg2img rootfs.img rootfs.raw` 展开根分区，在 Linux 通过 loop 挂载其副本。用 ARM64 环境安装新版 DEB 至离线根分区并检查 dpkg 状态。验证显示服务入口、钩子以及两个 ABI 的模块路径。
3. 清除发布副本中的历史、主机身份和预生成的设备密钥。可参考 `packaging/sanitize-public.sh` 中的本次发布处理。卸载后运行 `btrfs check --readonly rootfs.raw`，再用 `img2simg rootfs.raw rootfs.img 4096` 打回稀疏镜像。再次展开后与原始 rootfs 逐字节比对。
4. 将更新后的 rootfs 与其余分区按 `package-file` 用 AFPTool 打包，再用 `RKImageMaker -RK330C boot.bin firmware.rkaf update.img -os_type:ANDROIDOS` 生成单个 IMG。重新解包并对照每个分区的 SHA-256。
5. 用 7-Zip 压缩 IMG，再解压并比对 IMG 的 SHA-256。将 7z、DEB 和校验文件上传到 GitHub Release。`packaging/pack-public.ps1` 是本次验证和压缩流程，按脚本中的路径准备 RKDevTool、解包后的输入以及重建的 DEB。

发布前实测 6.12 冷启动和官方升级至 6.18。串口确认面板 LP 初始化成功、回读 `0x9c`，实体屏跨分钟观察时钟和温度刷新。
