import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_yarmy/app/yarmy_app.dart';

void main() {
  testWidgets('shows camera placeholder as the first screen', (tester) async {
    await tester.pumpWidget(const YarmyApp());

    expect(find.text('Yarmy'), findsOneWidget);
    expect(find.text('Камера будет здесь'), findsOneWidget);
    expect(
      find.text('Скоро здесь появится съемка настоящих историй до 60 секунд.'),
      findsOneWidget,
    );
  });
}
