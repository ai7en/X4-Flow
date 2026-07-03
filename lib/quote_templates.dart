import 'package:flutter/material.dart';
import 'device_profile.dart';
import 'book_quote.dart';
import 'quotes_ru.dart';
import 'quotes_en.dart';

// 🌐 Функция выбора цитат по языку
List<BookQuote> getBookQuotes(String lang) {
  return lang == 'en' ? bookQuotesEn : bookQuotesRu;
}

class QuoteBackground {
  final String nameRu;
  final String nameEn;
  final bool inverted;
  final String pattern;
  const QuoteBackground({
    required this.nameRu,
    required this.nameEn,
    required this.inverted,
    required this.pattern,
  });
  String name(String lang) => lang == 'en' ? nameEn : nameRu;
}

// 🎨 8 стилей оформления цитат
const List<QuoteBackground> quoteBackgrounds = [
  QuoteBackground(nameRu: 'Классика', nameEn: 'Classic', inverted: false, pattern: 'solid'),
  QuoteBackground(nameRu: 'Инверсия', nameEn: 'Inverted', inverted: true, pattern: 'solid'),
  QuoteBackground(nameRu: 'Рамка', nameEn: 'Frame', inverted: false, pattern: 'border'),
  QuoteBackground(nameRu: 'Рамка инв.', nameEn: 'Frame inv.', inverted: true, pattern: 'border'),
  QuoteBackground(nameRu: 'Минимализм', nameEn: 'Minimal', inverted: false, pattern: 'minimal'),
  QuoteBackground(nameRu: 'Книжная страница', nameEn: 'Book page', inverted: false, pattern: 'bookpage'),
  QuoteBackground(nameRu: 'Геометрия', nameEn: 'Geometry', inverted: false, pattern: 'geometry'),
  QuoteBackground(nameRu: 'Контраст', nameEn: 'Contrast', inverted: true, pattern: 'contrast'),
];

void drawQuoteOnCanvas(
  Canvas canvas,
  DeviceProfile profile,
  int quoteIndex,
  int bgIndex,
  double fontSize,
  String langCode,
) {
  final bg = quoteBackgrounds[bgIndex];
  final quotes = getBookQuotes(langCode);
  final safeIndex = quoteIndex % quotes.length;
  final quote = quotes[safeIndex];

  final w = profile.width.toDouble();
  final h = profile.height.toDouble();

  // === 1. ЦВЕТА ===
  final Color bgColor;
  final Color fgColor;
  final Color textColor;
  final Color mutedColor;

  if (bg.pattern == 'contrast') {
    // Контраст: белый фон + чёрная плашка с белым текстом
    bgColor = Colors.white;
    fgColor = Colors.black;
    textColor = Colors.white;
    mutedColor = Colors.white.withValues(alpha: 0.7);
  } else {
    bgColor = bg.inverted ? Colors.black : Colors.white;
    fgColor = bg.inverted ? Colors.white : Colors.black;
    textColor = fgColor;
    mutedColor = bg.inverted
        ? Colors.white.withValues(alpha: 0.7)
        : Colors.black.withValues(alpha: 0.6);
  }

  // === 2. ФОН ===
  canvas.drawRect(
    Rect.fromLTWH(0, 0, w, h),
    Paint()..color = bgColor,
  );

  // === 3. ДЕКОР (в зависимости от pattern) ===
  if (bg.pattern == 'border') {
    // Двойная рамка (классика)
    final borderPaint = Paint()
      ..color = fgColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawRect(Rect.fromLTWH(30, 30, w - 60, h - 60), borderPaint);
    final innerBorder = Paint()
      ..color = fgColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(Rect.fromLTWH(40, 40, w - 80, h - 80), innerBorder);
  } else if (bg.pattern == 'bookpage') {
    // Имитация книжной страницы: вертикальная линия слева (корешок) + номер страницы
    final spinePaint = Paint()
      ..color = fgColor.withValues(alpha: 0.4)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(w * 0.12, 20), Offset(w * 0.12, h - 20), spinePaint);
    final spinePaint2 = Paint()
      ..color = fgColor.withValues(alpha: 0.2)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(w * 0.12 + 4, 20), Offset(w * 0.12 + 4, h - 20), spinePaint2);
    // Номер страницы внизу
    final pageNumStyle = TextStyle(
      fontSize: 14,
      color: mutedColor,
      fontFamily: 'serif',
      fontStyle: FontStyle.italic,
    );
    final pageNum = TextPainter(
      text: TextSpan(text: '— 7 —', style: pageNumStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    pageNum.paint(canvas, Offset((w - pageNum.width) / 2, h - 40));
  } else if (bg.pattern == 'geometry') {
    // Диагональные линии в углах + круги
    final linePaint = Paint()
      ..color = fgColor.withValues(alpha: 0.3)
      ..strokeWidth = 3;
    canvas.drawLine(const Offset(0, 0), Offset(w * 0.3, h * 0.3), linePaint);
    canvas.drawLine(Offset(w, h), Offset(w * 0.7, h * 0.7), linePaint);
    final circlePaint = Paint()
      ..color = fgColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(Offset(w - 60, 60), 30, circlePaint);
    canvas.drawCircle(Offset(60, h - 60), 20, circlePaint);
  } else if (bg.pattern == 'contrast') {
    // Чёрная плашка в центре белого фона
    final plaqueRect = Rect.fromCenter(
      center: Offset(w / 2, h / 2),
      width: w * 0.85,
      height: h * 0.55,
    );
    canvas.drawRect(plaqueRect, Paint()..color = Colors.black);
  }
  // 'solid' и 'minimal' — только фон, без декора

  // === 4. ГИГАНТСКАЯ КАВЫЧКА (только для solid и border) ===
  if (bg.pattern == 'solid' || bg.pattern == 'border') {
    final quoteMarkStyle = TextStyle(
      fontSize: 200,
      color: fgColor.withValues(alpha: 0.15),
      fontFamily: 'serif',
      fontWeight: FontWeight.bold,
      height: 0.8,
    );
    final quoteMarkPainter = TextPainter(
      text: TextSpan(text: '«', style: quoteMarkStyle),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: w);
    quoteMarkPainter.paint(canvas, const Offset(30, 40));
  }

  // === 5. ТЕКСТ ЦИТАТЫ ===
  // Для книжной страницы сдвигаем текст правее (учитывая корешок)
  final double textLeft = bg.pattern == 'bookpage' ? w * 0.18 : 40;
  final double textRight = bg.pattern == 'bookpage' ? w * 0.06 : 40;
  final double maxWidth = w - textLeft - textRight;

  // Для книжной страницы чуть уменьшаем шрифт, чтобы текст помещался
  final double adjustedFontSize = bg.pattern == 'bookpage' ? fontSize * 0.9 : fontSize;

  final quoteChar = langCode == 'en' ? '"' : '«';
  final quoteCharEnd = langCode == 'en' ? '"' : '»';

  final quoteStyle = TextStyle(
    fontSize: adjustedFontSize,
    color: textColor,
    fontFamily: 'serif',
    fontWeight: FontWeight.w500,
    height: 1.4,
    letterSpacing: 0.3,
  );
  final quotePainter = TextPainter(
    text: TextSpan(text: '$quoteChar${quote.text}$quoteCharEnd', style: quoteStyle),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout(maxWidth: maxWidth);

  final quoteY = (h - quotePainter.height) / 2 - (bg.pattern == 'bookpage' ? 30 : 40);
  quotePainter.paint(canvas, Offset(textLeft + (maxWidth - quotePainter.width) / 2, quoteY));

  // === 6. РАЗДЕЛИТЕЛЬНАЯ ЛИНИЯ (кроме minimal) ===
  final lineY = quoteY + quotePainter.height + 20;
  if (bg.pattern != 'minimal') {
    final linePaint = Paint()
      ..color = textColor
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(w / 2 - 60, lineY),
      Offset(w / 2 + 60, lineY),
      linePaint,
    );
  }

  // === 7. АВТОР ===
  final authorStyle = TextStyle(
    fontSize: adjustedFontSize * 0.55,
    color: textColor,
    fontFamily: 'sans-serif',
    fontWeight: FontWeight.w600,
    fontStyle: FontStyle.italic,
    letterSpacing: 0.8,
  );
  final authorPainter = TextPainter(
    text: TextSpan(text: '— ${quote.author}', style: authorStyle),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.right,
  )..layout(maxWidth: maxWidth);
  authorPainter.paint(
    canvas,
    Offset(w - authorPainter.width - (bg.pattern == 'bookpage' ? textRight : 60), lineY + 15),
  );

  // === 8. КНИГА ===
  final bookStyle = TextStyle(
    fontSize: adjustedFontSize * 0.45,
    color: mutedColor,
    fontFamily: 'sans-serif',
    fontWeight: FontWeight.w400,
    letterSpacing: 0.8,
  );
  final bookPainter = TextPainter(
    text: TextSpan(text: quote.book, style: bookStyle),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.right,
  )..layout(maxWidth: maxWidth);
  bookPainter.paint(
    canvas,
    Offset(w - bookPainter.width - (bg.pattern == 'bookpage' ? textRight : 60), lineY + 45),
  );
}