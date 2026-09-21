import 'dart:mirrors';
import 'package:dartssh2/dartssh2.dart';

void main() {
  final mirror = reflectClass(SSHKeyPair);
  for (var decl in mirror.declarations.values) {
    print('\${decl.simpleName} : \$decl');
  }
}
