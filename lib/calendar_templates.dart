import 'package:flutter/material.dart';
import 'device_profile.dart';

List<String> getMonthNames(String lang) {
  if (lang == 'en') {
    return ['January', 'February', 'March', 'April', 'May', 'June',
            'July', 'August', 'September', 'October', 'November', 'December'];
  }
  return ['Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
          'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'];
}

List<String> getWeekDays(String lang) {
  if (lang == 'en') {
    return ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  }
  return ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
}

bool isWeekend(DateTime date) =>
    date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;

void drawCalendarOnCanvas(
  Canvas canvas,
  DeviceProfile profile,
  DateTime calendarDate,
  bool invertColors,
  String langCode,
) {
  final monthNames = getMonthNames(langCode);
  final weekDays = getWeekDays(langCode);
  final isEn = langCode == 'en';

  final bgColor = invertColors ? Colors.black : Colors.white;
  final fgColor = invertColors ? Colors.white : Colors.black;
  final mutedColor = invertColors
      ? Colors.white.withValues(alpha: 0.6)
      : Colors.black.withValues(alpha: 0.5);

  canvas.drawRect(
    Rect.fromLTWH(0, 0, profile.width.toDouble(), profile.height.toDouble()),
    Paint()..color = bgColor,
  );

  final year = calendarDate.year;
  final month = calendarDate.month;

  final borderPaint = Paint()
    ..color = fgColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3;
  canvas.drawRect(
    Rect.fromLTWH(20, 20, profile.width - 40, profile.height - 40),
    borderPaint,
  );
  final innerBorder = Paint()
    ..color = fgColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  canvas.drawRect(
    Rect.fromLTWH(28, 28, profile.width - 56, profile.height - 56),
    innerBorder,
  );

  final titleStyle = TextStyle(
    fontSize: 44,
    color: fgColor,
    fontFamily: 'serif',
    fontWeight: FontWeight.w600,
    letterSpacing: 3,
  );
  final titlePainter = TextPainter(
    text: TextSpan(text: monthNames[month - 1].toUpperCase(), style: titleStyle),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout(maxWidth: profile.width - 80);
  titlePainter.paint(canvas, Offset((profile.width - titlePainter.width) / 2, 60));

  final yearStyle = TextStyle(
    fontSize: 20,
    color: mutedColor,
    fontFamily: 'sans-serif',
    fontWeight: FontWeight.w400,
    letterSpacing: 6,
  );
  final yearPainter = TextPainter(
    text: TextSpan(text: year.toString(), style: yearStyle),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout(maxWidth: profile.width - 80);
  yearPainter.paint(canvas, Offset((profile.width - yearPainter.width) / 2, 115));

  final linePaint = Paint()
    ..color = fgColor
    ..strokeWidth = 1.5;
  canvas.drawLine(const Offset(50, 155), Offset(profile.width - 50, 155), linePaint);

  const double tableTop = 180;
  final double tableWidth = profile.width - 80;
  final double cellWidth = tableWidth / 7;
  const double cellHeight = 95;

  final headerStyle = TextStyle(
    fontSize: 16,
    fontFamily: 'sans-serif',
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
  );
  for (int i = 0; i < 7; i++) {
    final isW = isEn ? (i == 0 || i == 6) : (i == 5 || i == 6);
    final style = headerStyle.copyWith(
      color: fgColor,
      fontStyle: isW ? FontStyle.italic : FontStyle.normal,
    );
    final dayPainter = TextPainter(
      text: TextSpan(text: weekDays[i], style: style),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: cellWidth);
    final x = 40 + i * cellWidth + (cellWidth - dayPainter.width) / 2;
    dayPainter.paint(canvas, Offset(x, tableTop));
  }

  canvas.drawLine(
    Offset(40, tableTop + 30),
    Offset(profile.width - 40, tableTop + 30),
    linePaint..strokeWidth = 1,
  );

  final firstDayOfMonth = DateTime(year, month, 1);
  final daysInMonth = DateTime(year, month + 1, 0).day;
  final int startOffset = isEn
      ? firstDayOfMonth.weekday % 7
      : firstDayOfMonth.weekday - 1;

  final dayStyle = TextStyle(
    fontSize: 26,
    fontFamily: 'sans-serif',
    fontWeight: FontWeight.w500,
  );

  for (int day = 1; day <= daysInMonth; day++) {
    final date = DateTime(year, month, day);
    final index = startOffset + day - 1;
    final row = index ~/ 7;
    final col = index % 7;

    final x = 40 + col * cellWidth;
    final y = tableTop + 45 + row * cellHeight;
    final center = Offset(x + cellWidth / 2, y + cellHeight / 2);

    final isW = isWeekend(date);

    if (isW) {
      final squareSize = 38.0;
      final squareRect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: squareSize, height: squareSize),
        const Radius.circular(7),
      );
      final squarePaint = Paint()
        ..color = fgColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawRRect(squareRect, squarePaint);
    }

    final style = dayStyle.copyWith(
      color: fgColor,
      fontWeight: isW ? FontWeight.w700 : FontWeight.w500,
      fontStyle: isW ? FontStyle.italic : FontStyle.normal,
    );

    final dayPainter = TextPainter(
      text: TextSpan(text: day.toString(), style: style),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: cellWidth);
    dayPainter.paint(
      canvas,
      Offset(x + (cellWidth - dayPainter.width) / 2, y + (cellHeight - dayPainter.height) / 2),
    );
  }
}