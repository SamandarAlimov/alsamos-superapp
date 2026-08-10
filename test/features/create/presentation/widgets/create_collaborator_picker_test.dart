import 'dart:async';

import 'package:alsamos_flutter/app/theme/app_theme.dart';
import 'package:alsamos_flutter/features/create/data/models/create_collaborator.dart';
import 'package:alsamos_flutter/features/create/presentation/widgets/create_collaborator_picker.dart';
import 'package:alsamos_flutter/shared/stories/story_presence_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

void main() {
  const samandar = CreateCollaborator(
    id: 'user-1',
    username: 'samandar',
    displayName: 'Samandar',
  );

  Widget subject({
    required CreateCollaboratorSearch onSearch,
    CreateCollaboratorError? onError,
    List<CreateCollaborator> collaborators = const [],
    ValueChanged<CreateCollaborator>? onSelected,
    ValueChanged<CreateCollaborator>? onRemove,
  }) {
    final theme = AppTheme.light;
    return ProviderScope(
      overrides: [
        storyPresenceControllerProvider.overrideWith(
          (ref) => StoryPresenceController(
            loader: (_) async => const {},
          ),
        ),
      ],
      child: MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Builder(
            builder: (context) => CreateCollaboratorsSection(
              collaborators: collaborators,
              onAdd: () async {
                final selected = await showCreateCollaboratorPicker(
                  context: context,
                  onSearch: onSearch,
                  onError: onError ?? (_) {},
                );
                if (selected != null) onSelected?.call(selected);
              },
              onRemove: onRemove ?? (_) {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('keeps the selected collaborators section visually stable',
      (tester) async {
    CreateCollaborator? removed;

    await tester.pumpWidget(
      subject(
        collaborators: const [samandar],
        onSearch: (_) async => const [],
        onRemove: (user) => removed = user,
      ),
    );

    expect(find.text('Hamkorlar'), findsOneWidget);
    expect(find.text('Qo\'shish'), findsOneWidget);
    expect(find.text('@samandar'), findsOneWidget);

    await tester.tap(find.byIcon(LucideIcons.x).first);
    await tester.pump();

    expect(removed, samandar);
    expect(tester.takeException(), isNull);
  });

  testWidgets('searches after two characters and returns the selected user',
      (tester) async {
    final queries = <String>[];
    CreateCollaborator? selected;

    await tester.pumpWidget(
      subject(
        onSearch: (query) async {
          queries.add(query);
          return const [samandar];
        },
        onSelected: (user) => selected = user,
      ),
    );

    await tester.tap(find.text('Qo\'shish'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('create-collaborator-search-field')),
      's',
    );
    await tester.pump();

    expect(queries, isEmpty);

    await tester.enterText(
      find.byKey(const Key('create-collaborator-search-field')),
      '@sa',
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(queries, ['sa']);
    expect(find.text('Samandar'), findsOneWidget);
    expect(find.text('@samandar'), findsOneWidget);

    await tester.tap(find.text('Samandar'));
    await tester.pumpAndSettle();

    expect(selected, samandar);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reports async search errors through the error callback',
      (tester) async {
    final errors = <Object>[];
    final failure = Exception('search failed');

    await tester.pumpWidget(
      subject(
        onSearch: (_) async => throw failure,
        onError: errors.add,
      ),
    );

    await tester.tap(find.text('Qo\'shish'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('create-collaborator-search-field')),
      'sa',
    );
    await tester.pumpAndSettle();

    expect(errors, [failure]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ignores a stale result after query becomes too short',
      (tester) async {
    final pending = Completer<List<CreateCollaborator>>();

    await tester.pumpWidget(
      subject(onSearch: (_) => pending.future),
    );
    await tester.tap(find.text('Qo\'shish'));
    await tester.pumpAndSettle();

    final field = find.byKey(const Key('create-collaborator-search-field'));
    await tester.enterText(field, 'sa');
    await tester.pump();
    await tester.enterText(field, 's');
    await tester.pump();

    pending.complete(const [samandar]);
    await tester.pumpAndSettle();

    expect(find.text('Samandar'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
