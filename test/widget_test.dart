import 'package:flutter_test/flutter_test.dart';
import 'package:x4_companion/main.dart'; // Проверь, чтобы имя пакета совпадало с твоим проектом

void main() {
  testWidgets('Приложение запускается успешно', (WidgetTester tester) async {
      // Ждем, пока наше новое приложение отрендерится
          await tester.pumpWidget(const X4CompanionApp());

              // Проверяем, что на главном экране появился текст прошивки
                  expect(find.text('Прошивка Xteink X4'), findsOneWidget);
                    });
                    }
                    