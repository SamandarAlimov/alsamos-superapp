import 'package:flutter_test/flutter_test.dart';
import 'package:alsamos_flutter/features/messages/data/models/message_format.dart';

void main() {
  group('canonical message formatter', () {
    test('parses the same block semantics as React web', () {
      final blocks = parseMessageBlocks(
        '# Heading\n'
        '## Subheading\n'
        '> Quote\n'
        '- Bullet\n'
        '2. Ordered\n'
        '---\n'
        '\`\`\`dart\n'
        'print("ok");\n'
        '\`\`\`',
      );

      expect(
        blocks.map((block) => block.type).toList(),
        [
          MessageBlockType.heading1,
          MessageBlockType.heading2,
          MessageBlockType.quote,
          MessageBlockType.bullet,
          MessageBlockType.ordered,
          MessageBlockType.divider,
          MessageBlockType.pre,
        ],
      );
      expect(blocks[4].index, 2);
      expect(blocks.last.language, 'dart');
      expect(blocks.last.text, 'print("ok");');
    });

    test('parses nested inline formatting and explicit links', () {
      final nodes = parseMessageInline(
        '**bold __italic__** ++under++ ~~strike~~ '
        '`code` ||secret|| [Alsamos](https://alsamos.com)',
      );

      expect(nodes.any((node) => node.type == MessageInlineType.bold), isTrue);
      expect(nodes.any((node) => node.type == MessageInlineType.underline), isTrue);
      expect(nodes.any((node) => node.type == MessageInlineType.strike), isTrue);
      expect(nodes.any((node) => node.type == MessageInlineType.code), isTrue);
      expect(nodes.any((node) => node.type == MessageInlineType.spoiler), isTrue);

      final link = nodes.firstWhere((node) => node.type == MessageInlineType.link);
      expect(link.href, 'https://alsamos.com');
      expect(link.children.single.text, 'Alsamos');

      final bold = nodes.firstWhere((node) => node.type == MessageInlineType.bold);
      expect(
        bold.children.any((node) => node.type == MessageInlineType.italic),
        isTrue,
      );
    });

    test('strips transport markers for previews', () {
      expect(
        stripMessageFormatting(
          '# **Title**\n> ++Text++ [link](https://alsamos.com)',
        ),
        contains('Title'),
      );
      expect(
        stripMessageFormatting('**bold** ||secret||'),
        'bold secret',
      );
    });
  });
}
