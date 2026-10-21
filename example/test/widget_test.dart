import 'package:flutter_test/flutter_test.dart';
import 'package:transxact_flutter_example/main.dart';

void main() {
  testWidgets('shows the cart with the pay button', (tester) async {
    await tester.pumpWidget(const ExampleApp());

    expect(find.text('Order #1001'), findsOneWidget);
    expect(find.text('Pay with M-PAiSA or MyCash'), findsOneWidget);
  });
}
