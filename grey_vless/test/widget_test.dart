import 'package:flutter_test/flutter_test.dart';
import 'package:grey_vless/main.dart';

void main() {
  testWidgets('Grey vless smoke', (tester) async {
    await tester.pumpWidget(const GreyVlessApp());
    expect(find.text('Grey vless'), findsOneWidget);
  });
}
