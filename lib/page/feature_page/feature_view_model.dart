import 'package:android_tool/page/common/app.dart';
import 'package:android_tool/page/common/base_view_model.dart';
import 'package:android_tool/widget/input_dialog.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/src/widgets/framework.dart';
import 'package:process_run/shell_run.dart';

class FeatureViewModel extends BaseViewModel {
  String deviceId;
  String packageName;

  FeatureViewModel(
    BuildContext context,
    this.deviceId,
    this.packageName,
  ) : super(context) {
    App().getAdbPath().then((value) => adbPath = value);
    App().eventBus.on<DeviceIdEvent>().listen((event) {
      deviceId = event.deviceId;
    });
    App().eventBus.on<PackageNameEvent>().listen((event) {
      packageName = event.packageName;
    });
  }

  /// 选择文件安装应用
  void install() async {
    final typeGroup = XTypeGroup(label: 'apk', extensions: ['apk']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    installApk(deviceId, file?.path ?? "");
  }

  /// 卸载应用
  void uninstallApk() async {
    var result = await execAdb([
      '-s',
      deviceId,
      'uninstall',
      packageName,
    ]);
    // getInstalledApp(deviceId);
    if (result != null && result.exitCode == 0) {
      App().eventBus.fire("refresh");
    }
    showResultDialog(
      content: result != null && result.exitCode == 0 ? "卸载成功" : "卸载失败",
    );
  }

  /// 停止运行应用
  Future<void> stopApp({bool isShowResult = true}) async {
    var result = await execAdb([
      '-s',
      deviceId,
      'shell',
      'am',
      'force-stop',
      packageName,
    ]);
    if (isShowResult) {
      showResultDialog(isSuccess: result != null && result.exitCode == 0);
    }
  }

  /// 启动应用
  Future<void> startApp() async {
    var launchActivity = await _getLaunchActivity();
    var result = await execAdb([
      '-s',
      deviceId,
      'shell',
      'am',
      'start',
      '-n',
      launchActivity,
    ]);
    showResultDialog(isSuccess: result != null && result.exitCode == 0);
  }

  /// 获取启动Activity
  Future<String> _getLaunchActivity() async {
    var launchActivity = await execAdb([
      '-s',
      deviceId,
      'shell',
      'dumpsys',
      'package',
      packageName,
      '|',
      'grep',
      '-A',
      '1',
      'MAIN',
    ]);
    if (launchActivity == null) return "";
    var outLines = launchActivity.outLines;
    if (outLines.isEmpty) {
      return "";
    } else {
      for (var value in outLines) {
        if (value.contains("$packageName/")) {
          return value.substring(
              value.indexOf("$packageName/"), value.indexOf(" filter"));
        }
      }
      return "";
    }
  }

  /// 重启应用
  Future<void> restartApp() async {
    await stopApp(isShowResult: false);
    await startApp();
  }

  /// 清除数据
  Future<void> clearAppData() async {
    await execAdb([
      '-s',
      deviceId,
      'shell',
      'pm',
      'clear',
      packageName,
    ]);
  }

  /// 重置应用权限
  Future<void> resetAppPermission() async {
    var permissionList = await getAppPermissionList();
    for (var value in permissionList) {
      await execAdb([
        '-s',
        deviceId,
        'shell',
        'pm',
        'revoke',
        packageName,
        value,
      ]);
    }
  }

  /// 授予应用权限
  Future<void> grantAppPermission() async {
    var permissionList = await getAppPermissionList();
    for (var value in permissionList) {
      await execAdb([
        '-s',
        deviceId,
        'shell',
        'pm',
        'grant',
        packageName,
        value,
      ]);
    }
  }

  /// 获取应用权限列表
  Future<List<String>> getAppPermissionList() async {
    var permission = await execAdb([
      '-s',
      deviceId,
      'shell',
      'dumpsys',
      'package',
      packageName,
    ]);
    if (permission == null) return [];
    var outLines = permission.outLines;
    List<String> permissionList = [];
    for (var value in outLines) {
      if (value.contains("permission.")) {
        var permissionLine = value.replaceAll(" ", "").split(":");
        if (permissionLine.isEmpty) {
          continue;
        }
        var permission = permissionLine[0];
        permissionList.add(permission);
      }
    }
    return permissionList;
  }

  /// 获取应用安装路径
  Future<void> getAppInstallPath() async {
    var installPath = await execAdb([
      '-s',
      deviceId,
      'shell',
      'pm',
      'path',
      packageName,
    ]);
    if (installPath == null || installPath.outLines.isEmpty) {
      return;
    } else {
      var path = "";
      for (var value in installPath.outLines) {
        path += value.replaceAll("package:", "");
      }
      showResultDialog(
        content: path,
      );
    }
  }

  /// 截图保存到电脑
  Future<void> screenshot() async {
    var path = await getDirectoryPath();
    if (path == null || path.isEmpty) return;
    var result = await execAdb([
      '-s',
      deviceId,
      'exec-out',
      'screencap',
      '-p',
      '>',
      '$path/screenshot${DateTime.now().millisecondsSinceEpoch}.png',
    ]);

    if (result != null && result.exitCode == 0) {
      showResultDialog(content: "截图保存成功");
    } else {
      showResultDialog(content: "截图保存失败");
    }
  }

  /// 录屏并保存到电脑
  Future<void> recordScreen() async {
    await shell.runExecutableArguments(adbPath, [
      '-s',
      deviceId,
      'shell',
      'screenrecord',
      '/sdcard/screenrecord.mp4',
    ]);
  }

  /// 停止录屏
  Future<void> stopRecordAndSave() async {
    shell.kill();
    var path = await getDirectoryPath();
    var pull = await execAdb([
      '-s',
      deviceId,
      'pull',
      '/sdcard/screenrecord.mp4',
      '$path/screenshot${DateTime.now().millisecondsSinceEpoch}.mp4',
    ]);
    await execAdb([
      '-s',
      deviceId,
      'shell',
      'rm',
      '/sdcard/screenrecord.mp4',
    ]);
    if (pull != null && pull.exitCode == 0) {
      showResultDialog(content: "录屏保存成功");
    } else {
      showResultDialog(content: "录屏保存失败");
    }
  }

  /// 输入文本
  Future<void> inputText() async {
    var text = await showInputDialog();
    if (text != null && text.isNotEmpty) {
      await execAdb([
        '-s',
        deviceId,
        'shell',
        'input',
        'text',
        text,
      ]);
    }
  }

  /// 查看前台Activity
  Future<void> getForegroundActivity() async {
    var result = await execAdb([
      '-s',
      deviceId,
      'shell',
      'dumpsys',
      'window',
      '|',
      'grep',
      'mCurrentFocus',
    ]);
    var outLines = result?.outLines;
    if (outLines == null || outLines.isEmpty) {
      showResultDialog(content: "没有前台Activity");
    } else {
      var activity = outLines.first.replaceAll("mCurrentFocus=", "");
      showResultDialog(content: activity);
    }
  }

  ///查看设备AndroidId
  Future<void> getAndroidId() async {
    var result = await execAdb([
      '-s',
      deviceId,
      'shell',
      'settings',
      'get',
      'secure',
      'android_id',
    ]);
    var outLines = result?.outLines;
    if (outLines == null || outLines.isEmpty) {
      showResultDialog(content: "没有AndroidId");
    } else {
      var androidId = outLines.first;
      showResultDialog(content: androidId);
    }
  }

  ///  查看设备系统版本
  Future<void> getDeviceVersion() async {
    var result = await execAdb(
        ['-s', deviceId, 'shell', 'getprop', 'ro.build.version.release']);
    showResultDialog(
      content: result != null && result.exitCode == 0
          ? "Android " + result.stdout
          : "获取失败",
    );
  }

  /// 查看设备IP地址
  Future<void> getDeviceIpAddress() async {
    var result = await execAdb([
      '-s',
      deviceId,
      'shell',
      'ifconfig',
      '|',
      'grep',
      'Mask',
    ]);
    var outLines = result?.outLines;
    if (outLines == null || outLines.isEmpty) {
      showResultDialog(content: "没有IP地址");
    } else {
      var ip = "";
      for (var value in outLines) {
        value = value.substring(value.indexOf("addr:"), value.length);
        ip += value.substring(0, value.indexOf(" ")) + "\n";
        print(value);
      }
      showResultDialog(content: ip);
    }
  }

  /// 查看设备Mac地址
  Future<void> getDeviceMac() async {
    var result = await execAdb([
      '-s',
      deviceId,
      'shell',
      'cat',
      '/sys/class/net/wlan0/address',
    ]);
    showResultDialog(
      content: result != null && result.exitCode == 0 ? result.stdout : "获取失败",
    );
  }

  /// 重启手机
  Future<void> reboot() async {
    var result = await execAdb([
      '-s',
      deviceId,
      'reboot',
    ]);
    showResultDialog(
      content: result != null && result.exitCode == 0 ? "重启成功" : "重启失败",
    );
  }

  Future<String?> showInputDialog({
    String title = "输入文本",
    String hintText = "输入文本",
  }) async {
    return await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return InputDialog(
          title: title,
          hintText: hintText,
        );
      },
    );
  }

  void onDragDone(DropDoneDetails details) {
    var files = details.files;
    if (files.isEmpty) {
      return;
    }
    for (var value in files) {
      if (value.path.endsWith(".apk")) {
        showInstallApkDialog(deviceId, value);
      }
    }
  }

  /// Home键
  void pressHome() async {
    await execAdb([
      '-s',
      deviceId,
      'shell',
      'input',
      'keyevent',
      '3',
    ]);
  }

  /// 返回键
  void pressBack() async {
    await execAdb([
      '-s',
      deviceId,
      'shell',
      'input',
      'keyevent',
      '4',
    ]);
  }

  /// 菜单键
  void pressMenu() async {
    await execAdb([
      '-s',
      deviceId,
      'shell',
      'input',
      'keyevent',
      '82',
    ]);
  }

  /// 增加音量
  void pressVolumeUp() async {
    await execAdb([
      '-s',
      deviceId,
      'shell',
      'input',
      'keyevent',
      '24',
    ]);
  }

  /// 减少音量
  void pressVolumeDown() async {
    await execAdb([
      '-s',
      deviceId,
      'shell',
      'input',
      'keyevent',
      '25',
    ]);
  }

  /// 静音
  void pressVolumeMute() async {
    await execAdb([
      '-s',
      deviceId,
      'shell',
      'input',
      'keyevent',
      '164',
    ]);
  }

  /// 电源键
  void pressPower() async {
    await execAdb([
      '-s',
      deviceId,
      'shell',
      'input',
      'keyevent',
      '26',
    ]);
  }

  /// 切换应用
  void pressSwitchApp() async {
    await execAdb([
      '-s',
      deviceId,
      'shell',
      'input',
      'keyevent',
      '187',
    ]);
  }

  /// 屏幕点击
  void pressScreen() async {
    var input = await showInputDialog(title: "请输入坐标", hintText: "x,y");
    if (input == null || input.isEmpty) {
      return;
    }
    if (!input.contains(",")) {
      showResultDialog(content: "请输入正确的坐标");
      return;
    }
    await execAdb([
      '-s',
      deviceId,
      'shell',
      'input',
      'tap',
      input.replaceAll(",", " "),
    ]);
  }

  /// 向上滑动
  void pressSwipeUp() async {
    await execAdb([
      '-s',
      deviceId,
      'shell',
      'input',
      'swipe',
      '300',
      '1000',
      '300',
      '300',
    ]);
  }

  /// 向下滑动
  void pressSwipeDown() async {
    await execAdb([
      '-s',
      deviceId,
      'shell',
      'input',
      'swipe',
      '300',
      '300',
      '300',
      '1000',
    ]);
  }

  /// 向左滑动
  void pressSwipeLeft() async {
    await execAdb([
      '-s',
      deviceId,
      'shell',
      'input',
      'swipe',
      '700',
      '300',
      '300',
      '300',
    ]);
  }

  /// 向右滑动
  void pressSwipeRight() async {
    await execAdb([
      '-s',
      deviceId,
      'shell',
      'input',
      'swipe',
      '300',
      '300',
      '700',
      '300',
    ]);
  }
}