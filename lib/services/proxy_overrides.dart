import 'dart:io';

class ProxyHttpOverrides extends HttpOverrides {
  ProxyHttpOverrides(this.proxyAddress);

  /// `host:port`，为空则走系统环境变量。
  final String? proxyAddress;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionTimeout = const Duration(seconds: 20);
    client.idleTimeout = const Duration(seconds: 30);
    client.userAgent = 'MediaDownloader/1.0 (Flutter macOS)';
    final address = proxyAddress?.trim();
    if (address != null && address.isNotEmpty) {
      client.findProxy = (uri) => 'PROXY $address';
    } else {
      client.findProxy = HttpClient.findProxyFromEnvironment;
    }
    return client;
  }

  static void apply(String? proxyAddress) {
    HttpOverrides.global = ProxyHttpOverrides(proxyAddress);
  }
}
