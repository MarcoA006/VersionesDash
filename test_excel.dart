import 'package:excel/excel.dart';
void main() {
  var style = CellStyle(backgroundColorHex: ExcelColor.fromHexString('#FF0000'));
  print(style);
}
