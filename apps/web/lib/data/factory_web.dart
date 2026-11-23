import 'package:idb_shim/idb_browser.dart';

IdbFactory openFactory() => getIdbFactory() ?? idbFactoryMemory;
