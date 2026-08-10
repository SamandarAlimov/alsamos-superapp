import 'package:alsamos_flutter/app/theme/app_theme.dart';
import 'package:alsamos_flutter/features/messages/presentation/widgets/message_search_in_conversation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

void main() {
  testWidgets('filters messages and jumps between matches', (tester) async {
    final highlighted = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MessageSearchInConversation(
            messages: [
              InConversationMessage(
                id: '1',
                content: 'Assalomu alaykum',
                createdAt: DateTime(2026),
              ),
              InConversationMessage(
                id: '2',
                content: 'Telegram exact search',
                createdAt: DateTime(2026),
              ),
              InConversationMessage(
                id: '3',
                content: 'Search highlight works',
                createdAt: DateTime(2026),
              ),
            ],
            onHighlight: highlighted.add,
            onClose: () {},
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'search');
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('1 of 2'), findsOneWidget);
    expect(highlighted, ['2']);

    await tester.tap(find.byIcon(LucideIcons.chevronDown));
    await tester.pump();

    expect(find.text('2 of 2'), findsOneWidget);
    expect(highlighted.last, '3');
  });
}
