import 'dart:io';
import 'dart:convert';

class ProxyServer {
  static HttpServer? _server;
  static int get port => _server?.port ?? 0;

  static Future<void> start() async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((HttpRequest request) async {
      final path = request.uri.path.substring(1); // remove leading slash
      if (path.isEmpty) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.close();
        return;
      }

      String targetUrl;
      try {
        targetUrl = utf8.decode(base64Url.decode(path));
      } catch (e) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.close();
        return;
      }

      try {
        final client = HttpClient()
          ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;

        final targetRequest = await client.getUrl(Uri.parse(targetUrl));
        
        // Copy request headers to target (especially range headers for seeking)
        request.headers.forEach((name, values) {
          final lowerName = name.toLowerCase();
          if (lowerName != 'host' && lowerName != 'connection' && lowerName != 'accept-encoding') {
            for (var value in values) {
              targetRequest.headers.add(name, value);
            }
          }
        });

        final targetResponse = await targetRequest.close();

        // Copy target headers to response
        request.response.statusCode = targetResponse.statusCode;
        targetResponse.headers.forEach((name, values) {
          for (var value in values) {
            request.response.headers.add(name, value);
          }
        });

        await targetResponse.pipe(request.response);
      } catch (e) {
        print("Proxy error: $e");
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.close();
      }
    });
  }

  static String getProxyUrl(String targetUrl) {
    if (_server == null) return targetUrl;
    final encoded = base64Url.encode(utf8.encode(targetUrl));
    return 'http://127.0.0.1:$port/$encoded';
  }
}
