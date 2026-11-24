import 'package:web/web.dart' as web;

void setDataTheme(String name) {
  web.document.documentElement?.setAttribute('data-theme', name);
}
