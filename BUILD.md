# 构建与维护

本仓库维护迅雷盒子 X1 的板级用户态源码、DEB 安装脚本、6.18 initramfs 钩子和线刷打包流程。重打包使用对应版本的固件及 DEB 作为基线。六个内核模块的 C 源码与原编译工作树目前缺失，内核模块作为已验证的二进制输入。更换内核 ABI 前需要恢复对应驱动源码，并使用新内核的配置、头文件和符号表重新编译与验证。

## 重建 DEB

在 Linux 或 WSL 安装 `dpkg-dev` 和 `kmod`。下载 Release 的 DEB 后执行：

```bash
bash build-deb.sh ./lshz-3399-dsi-timing_0.2.beta3+fix1_arm64.deb ./rebuilt.deb
```

脚本解包参考 DEB，覆盖 `src/` 中对应的可维护文件，检查六个模块的 vermagic，重建校验清单并打包。发布更新时同时更新 DEB 版本，避免包管理器把新版识别成同一版本。

## 重建线刷包

1. 用 RKImageMaker 解包已有线刷 IMG，取得 `boot.bin` 和 `firmware.img`。再用 AFPTool 解开 `firmware.img`，取得清单、GPT 参数、U-Boot、Trust、boot 与 rootfs。
2. 用 `simg2img rootfs.img rootfs.raw` 展开根分区，在 Linux 通过 loop 挂载其副本。用 ARM64 环境安装新版 DEB 至离线根分区并检查 dpkg 状态。验证显示服务入口、钩子以及两个 ABI 的模块路径。
3. 清除发布副本中的历史、主机身份和预生成的设备密钥。可参考 `packaging/sanitize-public.sh` 中的本次发布处理。卸载后运行 `btrfs check --readonly rootfs.raw`，再用 `img2simg rootfs.raw rootfs.img 4096` 打回稀疏镜像。再次展开后与原始 rootfs 逐字节比对。
4. 将更新后的 rootfs 与其余分区按 `package-file` 用 AFPTool 打包，再用 `RKImageMaker -RK330C boot.bin firmware.rkaf update.img -os_type:ANDROIDOS` 生成单个 IMG。重新解包并对照每个分区的 SHA-256。
5. 用 7-Zip 压缩 IMG，再解压并比对 IMG 的 SHA-256。将 7z、DEB 和校验文件上传到 GitHub Release。`packaging/pack-public.ps1` 是本次验证和压缩流程，按脚本中的路径准备 RKDevTool、解包后的输入以及重建的 DEB。

发布前实测 6.12 冷启动和官方升级至 6.18。串口确认面板 LP 初始化成功、回读 `0x9c`，实体屏跨分钟观察时钟和温度刷新。
