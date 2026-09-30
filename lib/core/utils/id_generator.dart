import 'package:uuid/uuid.dart';

const Uuid _uuid = Uuid();

String newId() => _uuid.v4();

String stableId(String seed) => _uuid.v5(Namespace.url.value, 'kharcha:$seed');
