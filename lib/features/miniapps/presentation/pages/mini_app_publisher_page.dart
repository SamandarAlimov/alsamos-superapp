// Publisher onboarding sahifasi: publisher yaratish, domen qo'shish va TXT orqali tasdiqlash.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/mini_app_publisher_repository.dart';

final miniAppPublisherRepositoryProvider =
    Provider<MiniAppPublisherRepository>((ref) {
  return MiniAppPublisherRepository(Supabase.instance.client);
});

final myPublishersProvider =
    FutureProvider.autoDispose<List<MiniAppPublisher>>((ref) async {
  return ref.read(miniAppPublisherRepositoryProvider).listMyPublishers();
});

const Map<String, String> kPublisherTypeLabels = <String, String>{
  'individual': 'Jismoniy shaxs',
  'company': 'Kompaniya',
  'government': 'Davlat tashkiloti',
  'non_profit': 'Notijorat tashkilot',
};

class MiniAppPublisherPage extends ConsumerStatefulWidget {
  const MiniAppPublisherPage({super.key});

  @override
  ConsumerState<MiniAppPublisherPage> createState() =>
      _MiniAppPublisherPageState();
}

class _MiniAppPublisherPageState extends ConsumerState<MiniAppPublisherPage> {
  final TextEditingController _handleController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _domainController = TextEditingController();
  String _type = 'individual';
  bool _busy = false;

  @override
  void dispose() {
    _handleController.dispose();
    _nameController.dispose();
    _domainController.dispose();
    super.dispose();
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _createPublisher() async {
    final handle = _handleController.text.trim().toLowerCase();
    final name = _nameController.text.trim();

    if (!isValidPublisherHandle(handle)) {
      _notify('Handle 3-32 belgi: kichik harf, raqam va _ bo\u2019lishi kerak.');
      return;
    }
    if (name.length < 2) {
      _notify('Nomni to\u2019liq kiriting.');
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(miniAppPublisherRepositoryProvider).createPublisher(
            handle: handle,
            name: name,
            type: _type,
          );
      _handleController.clear();
      _nameController.clear();
      ref.invalidate(myPublishersProvider);
      _notify('Publisher yaratildi.');
    } catch (error) {
      _notify('Xatolik: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addDomain(MiniAppPublisher publisher) async {
    final normalized = normalizePublisherDomain(_domainController.text);
    if (normalized == null) {
      _notify('Domenni to\u2019g\u2019ri kiriting, masalan: islom.uz');
      return;
    }

    setState(() => _busy = true);
    try {
      final domain = await ref.read(miniAppPublisherRepositoryProvider).addDomain(
            publisherId: publisher.id,
            domain: normalized,
          );
      _domainController.clear();
      ref.invalidate(myPublishersProvider);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('TXT yozuvini qo\u2019shing'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Domen: ${domain.domain}'),
              const SizedBox(height: 8),
              const Text('DNS panelida quyidagi TXT yozuvini qo\u2019shing:'),
              const SizedBox(height: 8),
              SelectableText(
                domain.verificationToken ?? '',
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Yozuvni domen ildiziga yoki _alsamos.<domen> ga qo\u2019yish mumkin. '
                'Tarqalishi 24 soatgacha davom etishi mumkin.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Clipboard.setData(
                  ClipboardData(text: domain.verificationToken ?? ''),
                );
                Navigator.of(context).pop();
              },
              child: const Text('Nusxalash'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Yopish'),
            ),
          ],
        ),
      );
    } catch (error) {
      _notify('Xatolik: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify(MiniAppPublisherDomain domain) async {
    setState(() => _busy = true);
    try {
      final verified =
          await ref.read(miniAppPublisherRepositoryProvider).verifyDomain(domain.id);
      ref.invalidate(myPublishersProvider);
      _notify(verified
          ? 'Domen tasdiqlandi.'
          : 'TXT yozuvi topilmadi. Biroz kutib qayta urinib ko\u2019ring.');
    } catch (error) {
      _notify('Xatolik: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final publishers = ref.watch(myPublishersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Publisher kabinetі')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Text(
              'Yangi publisher',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _handleController,
              decoration: const InputDecoration(
                labelText: 'Handle',
                prefixText: '@',
                helperText: 'Masalan: islomuz, instagram, meta',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Ko\u2019rinadigan nom',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: 'Turi',
                border: OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<String>>[
                for (final entry in kPublisherTypeLabels.entries)
                  DropdownMenuItem<String>(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
              ],
              onChanged: (value) => setState(() => _type = value ?? 'individual'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _createPublisher,
              child: const Text('Yaratish'),
            ),
            const Divider(height: 40),
            Text(
              'Mening publisherlarim',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            publishers.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Text('Yuklanmadi: $error'),
              data: (items) {
                if (items.isEmpty) {
                  return const Text('Hozircha publisher yo\u2019q.');
                }
                return Column(
                  children: <Widget>[
                    for (final publisher in items)
                      _PublisherCard(
                        publisher: publisher,
                        domainController: _domainController,
                        onAddDomain: () => _addDomain(publisher),
                        onVerify: _verify,
                        loadDomains: () => ref
                            .read(miniAppPublisherRepositoryProvider)
                            .listDomains(publisher.id),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PublisherCard extends StatelessWidget {
  const _PublisherCard({
    required this.publisher,
    required this.domainController,
    required this.onAddDomain,
    required this.onVerify,
    required this.loadDomains,
  });

  final MiniAppPublisher publisher;
  final TextEditingController domainController;
  final VoidCallback onAddDomain;
  final Future<void> Function(MiniAppPublisherDomain domain) onVerify;
  final Future<List<MiniAppPublisherDomain>> Function() loadDomains;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    publisher.name + '  @' + publisher.handle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (publisher.isVerified)
                  const Icon(Icons.verified, size: 18, color: Colors.blue),
              ],
            ),
            Text(
              (kPublisherTypeLabels[publisher.type] ?? publisher.type) +
                  ' \u00b7 ' +
                  publisher.verification,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: domainController,
                    decoration: const InputDecoration(
                      labelText: 'Domen qo\u2019shish',
                      hintText: 'islom.uz',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: onAddDomain, child: const Text('Qo\u2019shish')),
              ],
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<MiniAppPublisherDomain>>(
              future: loadDomains(),
              builder: (context, snapshot) {
                final domains = snapshot.data ?? const <MiniAppPublisherDomain>[];
                if (domains.isEmpty) {
                  return const Text('Domen qo\u2019shilmagan.');
                }
                return Column(
                  children: <Widget>[
                    for (final domain in domains)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: Icon(
                          domain.isVerified ? Icons.verified : Icons.pending_outlined,
                          color: domain.isVerified ? Colors.green : null,
                        ),
                        title: Text(domain.domain),
                        subtitle: Text(
                          domain.isVerified
                              ? 'Tasdiqlangan'
                              : (domain.checkError ?? 'TXT tekshiruvi kutilmoqda'),
                        ),
                        trailing: domain.isVerified
                            ? null
                            : TextButton(
                                onPressed: () => onVerify(domain),
                                child: const Text('Tekshirish'),
                              ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
