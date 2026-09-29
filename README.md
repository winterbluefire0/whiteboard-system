# Whiteboard Capture / 白板快拍

XIAO ESP32-S3 Sense 拍实体白板，Mac 校正并增强图片，再把彩色图复制到剪贴板，供你粘贴进喜欢的聊天工具。这个仓库是白板系统的**采集端原型**。

合成样例：[原图](examples/demo-board.jpg) → [彩色增强图](examples/demo-color.png)。示例由 `examples/make_demo.py` 生成，没有使用真实讨论内容。

## 已实现

1. 开发板通过 USB 拍摄 JPEG；也提供独立 Wi-Fi 热点网页预览。
2. Mac 菜单栏工具调试白板四角，用快捷键拍照。
3. 每次保存原图、彩色增强图、黑白增强图；彩色图复制到剪贴板。
4. 用户在聊天窗口粘贴图片，自行输入或语音转写讲解。

目前拍照后的粘贴由用户完成。这个仓库不包含聊天产品接口、记忆系统服务、自动录音或任务分发。记忆框架仍在私人材料上的试用阶段，成熟后会作为独立模块接入。

## 需要什么

- **硬件**：Seeed Studio XIAO ESP32-S3 Sense（装好摄像头扩展板），USB 数据线，实体白板。
- **电脑**：macOS，Python 3.9 或更新版本，Xcode Command Line Tools（提供 `clang`）。
- **首次刷固件**：PlatformIO 及 Espressif 平台；下面的 Python 依赖清单含 PlatformIO。

本机验证环境为 macOS、Python 3.9.6、PlatformIO 6.2.0、Espressif32 6.10.0。其它系统可以单独使用 USB 命令行拍照和 Python 增强脚本；菜单栏快捷键工具仅支持 macOS。

## 安装与第一次拍照

在仓库根目录运行：

```sh
python3 -m venv .tools/venv
.tools/venv/bin/python -m pip install -r requirements.txt
cp firmware/secrets.example.h firmware/secrets.h
```

编辑 `firmware/secrets.h`，设置**你自己的**热点名称和至少八位密码。此文件已被 Git 忽略。

将 XIAO 接到 Mac，编译并上传固件：

```sh
.tools/venv/bin/pio run
.tools/venv/bin/pio run --target upload
```

如自动选择了错误的串口，可在第二条命令加 `--upload-port /dev/cu.usbmodem...`，设备名以你的电脑为准。刷写前可先备份现有固件；上传会替换开发板当前程序。

检查相机，再拍一张测试照片：

```sh
.tools/venv/bin/python camera_usb.py status
.tools/venv/bin/python camera_usb.py photo
```

如果电脑同时接了多块 Espressif 开发板，用 `--port` 指定设备。照片保存在 `captures/`。

### 用快捷键拍白板

```sh
./quick-capture/build.sh
open 'quick-capture/Whiteboard Capture.app'
```

菜单栏会出现“白板”。

1. 按 **Control + Option + Command + P**，查看预览并调整机位；依次点白板内侧的左上、右上、右下、左下四角，确认选区。
2. 按 **Control + Option + Command + B** 拍新照片。听到提示音后，彩色增强图已进入剪贴板。
3. 回到聊天窗口，按 **Command + V**，检查图片，添加讲解文字，再发送。

每次重新打开工具都要确认一次位置。相机或白板移动后重新调试。拍照只改变系统剪贴板，不会自动发送给聊天模型。

原始照片在 `captures/`；每轮的三份图片与处理参数在 `enhancements/quick-capture/`。这些目录在 `.gitignore` 中，不会被提交。增强不会恢复被擦掉或反光遮住的笔迹。

## 不接硬件也能试增强

仓库提供一张程序生成的示例白板，内容是通用的 IDEA → ACTION，没有真实白板或对话资料。

```sh
.tools/venv/bin/python examples/make_demo.py
.tools/venv/bin/python enhance_whiteboard.py examples/demo-board.jpg --corners 130,105 1165,82 1110,802 154,768 --output enhancements/demo
```

输出文件夹里会有原图、`color.png`、`bw.png` 和处理参数。`--corners` 后的四个点依次为左上、右上、右下、左下；真实白板请在预览中重新点选。

## 当前验证状态

已在本机从依赖清单建立新的 Python 3.9 环境，成功编译固件和 Mac 菜单栏应用，并用合成示例生成三份图片。本次整理公开仓库时未连接开发板，因此未在公开版固件上重复 USB 实拍；拍照协议来自此前已实测的原型。其他人的相机接线、系统权限和快捷键占用情况仍需实际检查。

## 目录

| 位置 | 作用 |
| --- | --- |
| `firmware/` 与 `platformio.ini` | 摄像头固件及 USB/Wi-Fi 拍照接口 |
| `camera_usb.py` | 从 USB 读取状态或 JPEG |
| `enhance_whiteboard.py` | 透视校正、彩色及黑白增强 |
| `quick-capture/` | macOS 菜单栏应用与拍照流程 |
| `examples/` | 可公开的合成演示素材 |

## 范围与隐私

原图和增强图保存在本机；程序本身不上传图片。Wi-Fi 热点用于设备预览，没有互联网。请不要把个人白板照片、对话记录、`firmware/secrets.h` 或运行时目录提交到公开仓库。

本仓库按 MIT License 发布。欢迎报告不同机型或 macOS 版本上的复现问题；提问时请先隐藏个人图片和设备标识。
