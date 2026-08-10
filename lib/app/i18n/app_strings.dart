import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// v44: i18n 100% — ported from web `src/i18n/locales/{uz,en,ru}.json`.
/// 3 ta locale, \~110 ta key. Use `AppStrings.of(ref).t('nav.home')`.
enum AppLocale { uz, en, ru }

extension AppLocaleExt on AppLocale {
  String get code => name;
  String get label => switch (this) {
        AppLocale.uz => "O'zbek",
        AppLocale.en => 'English',
        AppLocale.ru => 'Русский',
      };
  String get flag => switch (this) {
        AppLocale.uz => '🇺🇿',
        AppLocale.en => '🇬🇧',
        AppLocale.ru => '🇷🇺',
      };
  Locale get flutterLocale => Locale(code);
}

class _LocaleNotifier extends StateNotifier<AppLocale> {
  _LocaleNotifier() : super(AppLocale.uz) { _load(); }
  static const _key = 'app.locale';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_key);
    if (code != null) {
      state = AppLocale.values.firstWhere((l) => l.code == code, orElse: () => AppLocale.uz);
    }
  }

  Future<void> setLocale(AppLocale l) async {
    state = l;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, l.code);
  }
}

final localeProvider =
    StateNotifierProvider<_LocaleNotifier, AppLocale>((ref) => _LocaleNotifier());

class AppStrings {
  final AppLocale locale;
  const AppStrings(this.locale);
  static AppStrings of(WidgetRef ref) => AppStrings(ref.watch(localeProvider));

  String t(String key) {
    final table = _all[locale] ?? _uz;
    return table[key] ?? _uz[key] ?? key;
  }

  static const _all = <AppLocale, Map<String, String>>{
    AppLocale.uz: _uz,
    AppLocale.en: _en,
    AppLocale.ru: _ru,
  };

  static const _uz = <String, String>{
    // common
    'common.save': 'Saqlash', 'common.cancel': 'Bekor qilish',
    'common.delete': "O'chirish", 'common.edit': 'Tahrirlash',
    'common.search': 'Qidirish', 'common.loading': 'Yuklanmoqda...',
    'common.send': 'Yuborish', 'common.back': 'Orqaga', 'common.close': 'Yopish',
    'common.confirm': 'Tasdiqlash', 'common.yes': 'Ha', 'common.no': "Yo'q",
    'common.more': 'Yana', 'common.settings': 'Sozlamalar', 'common.language': 'Til',
    'common.retry': 'Qayta urinish', 'common.share': 'Ulashish', 'common.copy': 'Nusxalash',
    'common.report': 'Shikoyat', 'common.block': 'Bloklash', 'common.mute': 'Ovozsiz',
    'common.next': 'Keyingi', 'common.previous': 'Oldingi', 'common.done': 'Tayyor',
    'common.skip': "O'tkazib yuborish", 'common.continue': 'Davom etish',
    'common.upload': 'Yuklash', 'common.publish': 'Joylash', 'common.draft': 'Qoralama',
    'common.add': "Qo'shish", 'common.remove': 'Olib tashlash', 'common.refresh': 'Yangilash',
    // nav
    'nav.home': 'Bosh sahifa', 'nav.search': 'Qidirish', 'nav.discover': 'Kashf etish',
    'nav.videos': 'Videolar', 'nav.messages': 'Xabarlar', 'nav.marketplace': 'Bozor',
    'nav.map': 'Xarita', 'nav.payment': "To'lov", 'nav.ai': 'AI yordamchi',
    'nav.miniApps': 'Mini ilovalar', 'nav.create': 'Yaratish', 'nav.profile': 'Profil',
    'nav.settings': 'Sozlamalar', 'nav.notifications': 'Bildirishnomalar',
    'nav.logout': 'Chiqish', 'nav.bookmarks': 'Saqlanganlar', 'nav.stories': 'Hikoyalar',
    'nav.channels': 'Kanallar', 'nav.live': 'Jonli efir', 'nav.admin': 'Admin',
    // settings
    'settings.title': 'Sozlamalar', 'settings.language': 'Til',
    'settings.languageDescription': 'Interfeys tilini tanlang',
    'settings.profile': 'Profil', 'settings.notifications': 'Bildirishnomalar',
    'settings.privacy': 'Maxfiylik', 'settings.appearance': "Ko'rinish",
    'settings.darkMode': "Tungi rejim", 'settings.security': 'Xavfsizlik',
    'settings.account': 'Hisob', 'settings.changePassword': "Parolni o'zgartirish",
    'settings.twoFactor': 'Ikki bosqichli autentifikatsiya', 'settings.devices': 'Qurilmalar',
    'settings.location': 'Joylashuv', 'settings.about': 'Ilova haqida',
    'settings.logoutConfirm': 'Rostdan chiqmoqchimisiz?',
    // settings groups
    'settings.group.account': 'Hisob',
    'settings.group.modules': 'Ilovalar',
    'settings.group.preferences': 'Sozlamalar',
    'settings.group.admin': 'Administratsiya',
    // settings items (module-aware)
    'settings.items.profile': 'Profilim',
    'settings.items.wallet': 'To\'lovlar',
    'settings.items.devices': 'Qurilmalar',
    'settings.items.security': 'Xavfsizlik',
    'settings.items.history': 'Ko\'rishlar tarixi',
    'settings.items.messages': 'Xabarlar',
    'settings.items.marketplace': 'Bozor',
    'settings.items.map': 'Xarita',
    'settings.items.video': 'Videolar',
    'settings.items.ai': 'AI yordamchi',
    'settings.items.notifications': 'Bildirishnomalar va ovozlar',
    'settings.items.privacy': 'Maxfiylik',
    'settings.items.appearance': "Ko'rinish va til",
    'settings.items.dataStorage': "Ma'lumotlar va xotira",
    'settings.items.adminPanel': 'Admin panel',
    // wallet settings
    'settings.wallet.balance': 'Balans',
    'settings.wallet.topUp': "To'ldirish",
    'settings.wallet.methods': "To'lov usullari",
    'settings.wallet.addMethod': "Yangi usul qo'shish",
    'settings.wallet.defaultCurrency': 'Asosiy valyuta',
    'settings.wallet.paymentPin': "To'lov PIN-kodi",
    'settings.wallet.transactionHistory': 'Tranzaksiyalar tarixi',
    'settings.wallet.limits': 'Limitlar',
    'settings.wallet.payout': "Pul yechish",
    // messages settings
    'settings.messages.chatBackground': 'Chat foni',
    'settings.messages.textSize': 'Matn o\'lchami',
    'settings.messages.enterToSend': 'Enter orqali yuborish',
    'settings.messages.autoDownload': 'Avtomatik yuklab olish',
    'settings.messages.folders': 'Chat jildlari',
    'settings.messages.savedMessages': 'Saqlangan xabarlar',
    // video settings
    'settings.video.autoplay': 'Avtomatik ijro',
    'settings.video.quality': 'Sifat',
    'settings.video.dataSaver': "Ma'lumot tejash",
    // data storage
    'settings.data.storageUsage': 'Xotira foydalanish',
    'settings.data.clearCache': 'Keshni tozalash',
    'settings.data.messagesCache': 'Xabarlar keshi',
    'settings.data.downloads': 'Yuklab olinganlar',
    // history
    'history.paused': 'Tarix yozish to\'xtatildi',
    'history.resumed': 'Tarix yozish davom ettirildi',
    'history.clearAll': 'Barcha tarixni tozalash',
    'history.clearConfirm': 'Barcha ko\'rish tarixini o\'chirmoqchimisiz? Bu harakatni bekor qilish mumkin emas.',
    'history.cleared': 'Tarix tozalandi',
    // pages
    'pages.notifications': 'Bildirishnomalar',
    'pages.notificationsEmpty': "Bildirishnomalar hali yo'q",
    'pages.notificationsMarkAll': 'Hammasini belgilash',
    'pages.videos': 'Videolar', 'pages.channels': 'Kanallar',
    'pages.admin': 'Admin paneli', 'pages.orders': 'Buyurtmalar',
    'pages.bookmarks': 'Saqlangan postlar', 'pages.feed': 'Tasma',
    'pages.stories': 'Hikoyalar', 'pages.followers': 'Obunachilar',
    'pages.following': 'Obunalar', 'pages.search': 'Qidiruv',
    // messages
    'messages.newMessage': 'Yangi xabar', 'messages.noMessages': "Xabarlar yo'q",
    'messages.online': 'Onlayn', 'messages.typing': 'Yozmoqda...',
    'messages.writeMessage': 'Xabar yozing...',
    'messages.delivered': 'Yetkazildi', 'messages.seen': "Ko'rildi",
    // post
    'post.like': 'Yoqdi', 'post.comment': 'Izoh', 'post.share': 'Ulashish',
    'post.repost': 'Repost', 'post.save': 'Saqlash', 'post.report': 'Shikoyat qilish',
    'post.views': 'Ko\'rishlar', 'post.createCaption': 'Nimani o\'ylayapsiz?',
    'post.publishCta': 'Joylash', 'post.deleteConfirm': 'Postni o\'chirmoqchimisiz?',
    // report dialog
    'report.title': 'Shikoyat qilish', 'report.subtitle': 'Sababini tanlang',
    'report.reasonSpam': 'Spam', 'report.reasonHarassment': 'Tahqirlash',
    'report.reasonHate': 'Nafrat tili', 'report.reasonViolence': 'Zo\'ravonlik',
    'report.reasonNudity': 'Nomaqbul kontent', 'report.reasonScam': 'Aldash',
    'report.reasonOther': 'Boshqa', 'report.detailsHint': 'Qo\'shimcha tafsilot (ixtiyoriy)',
    'report.submit': 'Yuborish', 'report.thanks': 'Shikoyat qabul qilindi, rahmat.',
    // video editor
    'videoEditor.title': 'Video tahrirlash', 'videoEditor.trim': 'Kesish',
    'videoEditor.crop': 'Kadrlash', 'videoEditor.filter': 'Filtr',
    'videoEditor.music': 'Musiqa', 'videoEditor.text': 'Matn',
    'videoEditor.export': 'Eksport', 'videoEditor.savingDraft': 'Qoralama saqlandi',
    // story
    'story.create': 'Hikoya yaratish', 'story.addText': 'Matn qo\'shish',
    'story.addSticker': 'Stiker', 'story.addMusic': 'Musiqa',
    'story.privacyEveryone': 'Hamma', 'story.privacyCloseFriends': 'Yaqin do\'stlar',
    'story.privacyOnlyMe': 'Faqat men',
    // a11y
    'a11y.openMenu': 'Menyuni ochish', 'a11y.closeMenu': 'Menyuni yopish',
    'a11y.openProfile': 'Profilni ochish', 'a11y.likeButton': 'Yoqtirish tugmasi',
    'a11y.commentButton': 'Izoh tugmasi', 'a11y.shareButton': 'Ulashish tugmasi',
    'a11y.zoomIn': 'Kattalashtirish', 'a11y.zoomOut': 'Kichraytirish',
  };

  static const _en = <String, String>{
    'common.save': 'Save', 'common.cancel': 'Cancel', 'common.delete': 'Delete',
    'common.edit': 'Edit', 'common.search': 'Search', 'common.loading': 'Loading...',
    'common.send': 'Send', 'common.back': 'Back', 'common.close': 'Close',
    'common.confirm': 'Confirm', 'common.yes': 'Yes', 'common.no': 'No',
    'common.more': 'More', 'common.settings': 'Settings', 'common.language': 'Language',
    'common.retry': 'Retry', 'common.share': 'Share', 'common.copy': 'Copy',
    'common.report': 'Report', 'common.block': 'Block', 'common.mute': 'Mute',
    'common.next': 'Next', 'common.previous': 'Previous', 'common.done': 'Done',
    'common.skip': 'Skip', 'common.continue': 'Continue', 'common.upload': 'Upload',
    'common.publish': 'Publish', 'common.draft': 'Draft', 'common.add': 'Add',
    'common.remove': 'Remove', 'common.refresh': 'Refresh',
    'nav.home': 'Home', 'nav.search': 'Search', 'nav.discover': 'Discover',
    'nav.videos': 'Videos', 'nav.messages': 'Messages', 'nav.marketplace': 'Marketplace',
    'nav.map': 'Map', 'nav.payment': 'Payment', 'nav.ai': 'AI Assistant',
    'nav.miniApps': 'Mini apps', 'nav.create': 'Create', 'nav.profile': 'Profile',
    'nav.settings': 'Settings', 'nav.notifications': 'Notifications',
    'nav.logout': 'Log out', 'nav.bookmarks': 'Bookmarks', 'nav.stories': 'Stories',
    'nav.channels': 'Channels', 'nav.live': 'Live', 'nav.admin': 'Admin',
    'settings.title': 'Settings', 'settings.language': 'Language',
    'settings.languageDescription': 'Choose the interface language',
    'settings.profile': 'Profile', 'settings.notifications': 'Notifications',
    'settings.privacy': 'Privacy', 'settings.appearance': 'Appearance',
    'settings.darkMode': 'Dark mode', 'settings.security': 'Security',
    'settings.account': 'Account', 'settings.changePassword': 'Change password',
    'settings.twoFactor': 'Two-factor authentication', 'settings.devices': 'Devices',
    'settings.location': 'Location', 'settings.about': 'About',
    'settings.logoutConfirm': 'Are you sure you want to log out?',
    // settings groups
    'settings.group.account': 'Account',
    'settings.group.modules': 'App Modules',
    'settings.group.preferences': 'Preferences',
    'settings.group.admin': 'Administration',
    // settings items (module-aware)
    'settings.items.profile': 'My Profile',
    'settings.items.wallet': 'Payments',
    'settings.items.devices': 'Devices',
    'settings.items.security': 'Security',
    'settings.items.history': 'Watch history',
    'settings.items.messages': 'Messages',
    'settings.items.marketplace': 'Marketplace',
    'settings.items.map': 'Map',
    'settings.items.video': 'Video',
    'settings.items.ai': 'AI Assistant',
    'settings.items.notifications': 'Notifications & Sounds',
    'settings.items.privacy': 'Privacy',
    'settings.items.appearance': 'Appearance & Language',
    'settings.items.dataStorage': 'Data & Storage',
    'settings.items.adminPanel': 'Admin Panel',
    // wallet settings
    'settings.wallet.balance': 'Balance',
    'settings.wallet.topUp': 'Top Up',
    'settings.wallet.methods': 'Payment Methods',
    'settings.wallet.addMethod': 'Add New Method',
    'settings.wallet.defaultCurrency': 'Default Currency',
    'settings.wallet.paymentPin': 'Payment PIN',
    'settings.wallet.transactionHistory': 'Transaction History',
    'settings.wallet.limits': 'Limits',
    'settings.wallet.payout': 'Withdraw',
    // messages settings
    'settings.messages.chatBackground': 'Chat Background',
    'settings.messages.textSize': 'Text Size',
    'settings.messages.enterToSend': 'Enter to Send',
    'settings.messages.autoDownload': 'Auto Download',
    'settings.messages.folders': 'Chat Folders',
    'settings.messages.savedMessages': 'Saved Messages',
    // video settings
    'settings.video.autoplay': 'Autoplay',
    'settings.video.quality': 'Quality',
    'settings.video.dataSaver': 'Data Saver',
    // data storage
    'settings.data.storageUsage': 'Storage Usage',
    'settings.data.clearCache': 'Clear Cache',
    'settings.data.messagesCache': 'Messages Cache',
    'settings.data.downloads': 'Downloads',
    // history
    'history.paused': 'History recording paused',
    'history.resumed': 'History recording resumed',
    'history.clearAll': 'Clear all history',
    'history.clearConfirm': 'Delete all viewing history? This cannot be undone.',
    'history.cleared': 'History cleared',
    'pages.notifications': 'Notifications',
    'pages.notificationsEmpty': 'No notifications yet',
    'pages.notificationsMarkAll': 'Mark all as read',
    'pages.videos': 'Videos', 'pages.channels': 'Channels',
    'pages.admin': 'Admin panel', 'pages.orders': 'Orders',
    'pages.bookmarks': 'Bookmarks', 'pages.feed': 'Feed',
    'pages.stories': 'Stories', 'pages.followers': 'Followers',
    'pages.following': 'Following', 'pages.search': 'Search',
    'messages.newMessage': 'New message', 'messages.noMessages': 'No messages',
    'messages.online': 'Online', 'messages.typing': 'Typing...',
    'messages.writeMessage': 'Write a message...',
    'messages.delivered': 'Delivered', 'messages.seen': 'Seen',
    'post.like': 'Like', 'post.comment': 'Comment', 'post.share': 'Share',
    'post.repost': 'Repost', 'post.save': 'Save', 'post.report': 'Report',
    'post.views': 'Views', 'post.createCaption': "What's on your mind?",
    'post.publishCta': 'Publish', 'post.deleteConfirm': 'Delete this post?',
    'report.title': 'Report', 'report.subtitle': 'Choose a reason',
    'report.reasonSpam': 'Spam', 'report.reasonHarassment': 'Harassment',
    'report.reasonHate': 'Hate speech', 'report.reasonViolence': 'Violence',
    'report.reasonNudity': 'Inappropriate content', 'report.reasonScam': 'Scam',
    'report.reasonOther': 'Other', 'report.detailsHint': 'Additional details (optional)',
    'report.submit': 'Submit', 'report.thanks': 'Report received, thank you.',
    'videoEditor.title': 'Edit video', 'videoEditor.trim': 'Trim',
    'videoEditor.crop': 'Crop', 'videoEditor.filter': 'Filter',
    'videoEditor.music': 'Music', 'videoEditor.text': 'Text',
    'videoEditor.export': 'Export', 'videoEditor.savingDraft': 'Draft saved',
    'story.create': 'Create story', 'story.addText': 'Add text',
    'story.addSticker': 'Sticker', 'story.addMusic': 'Music',
    'story.privacyEveryone': 'Everyone', 'story.privacyCloseFriends': 'Close friends',
    'story.privacyOnlyMe': 'Only me',
    'a11y.openMenu': 'Open menu', 'a11y.closeMenu': 'Close menu',
    'a11y.openProfile': 'Open profile', 'a11y.likeButton': 'Like button',
    'a11y.commentButton': 'Comment button', 'a11y.shareButton': 'Share button',
    'a11y.zoomIn': 'Zoom in', 'a11y.zoomOut': 'Zoom out',
  };

  static const _ru = <String, String>{
    'common.save': 'Сохранить', 'common.cancel': 'Отмена', 'common.delete': 'Удалить',
    'common.edit': 'Редактировать', 'common.search': 'Поиск', 'common.loading': 'Загрузка...',
    'common.send': 'Отправить', 'common.back': 'Назад', 'common.close': 'Закрыть',
    'common.confirm': 'Подтвердить', 'common.yes': 'Да', 'common.no': 'Нет',
    'common.more': 'Ещё', 'common.settings': 'Настройки', 'common.language': 'Язык',
    'common.retry': 'Повторить', 'common.share': 'Поделиться', 'common.copy': 'Копировать',
    'common.report': 'Пожаловаться', 'common.block': 'Заблокировать', 'common.mute': 'Без звука',
    'common.next': 'Далее', 'common.previous': 'Назад', 'common.done': 'Готово',
    'common.skip': 'Пропустить', 'common.continue': 'Продолжить',
    'common.upload': 'Загрузить', 'common.publish': 'Опубликовать', 'common.draft': 'Черновик',
    'common.add': 'Добавить', 'common.remove': 'Удалить', 'common.refresh': 'Обновить',
    'nav.home': 'Главная', 'nav.search': 'Поиск', 'nav.discover': 'Обзор',
    'nav.videos': 'Видео', 'nav.messages': 'Сообщения', 'nav.marketplace': 'Магазин',
    'nav.map': 'Карта', 'nav.payment': 'Оплата', 'nav.ai': 'ИИ-помощник',
    'nav.miniApps': 'Мини-приложения', 'nav.create': 'Создать', 'nav.profile': 'Профиль',
    'nav.settings': 'Настройки', 'nav.notifications': 'Уведомления',
    'nav.logout': 'Выйти', 'nav.bookmarks': 'Закладки', 'nav.stories': 'Истории',
    'nav.channels': 'Каналы', 'nav.live': 'Прямой эфир', 'nav.admin': 'Админ',
    'settings.title': 'Настройки', 'settings.language': 'Язык',
    'settings.languageDescription': 'Выберите язык интерфейса',
    'settings.profile': 'Профиль', 'settings.notifications': 'Уведомления',
    'settings.privacy': 'Конфиденциальность', 'settings.appearance': 'Внешний вид',
    'settings.darkMode': 'Тёмная тема', 'settings.security': 'Безопасность',
    'settings.account': 'Аккаунт', 'settings.changePassword': 'Сменить пароль',
    'settings.twoFactor': 'Двухфакторная аутентификация', 'settings.devices': 'Устройства',
    'settings.location': 'Местоположение', 'settings.about': 'О приложении',
    'settings.logoutConfirm': 'Вы уверены, что хотите выйти?',
    // settings groups
    'settings.group.account': 'Аккаунт',
    'settings.group.modules': 'Модули приложения',
    'settings.group.preferences': 'Настройки',
    'settings.group.admin': 'Администрирование',
    // settings items (module-aware)
    'settings.items.profile': 'Мой профиль',
    'settings.items.wallet': 'Платежи',
    'settings.items.devices': 'Устройства',
    'settings.items.security': 'Безопасность',
    'settings.items.history': 'История просмотров',
    'settings.items.messages': 'Сообщения',
    'settings.items.marketplace': 'Маркетплейс',
    'settings.items.map': 'Карта',
    'settings.items.video': 'Видео',
    'settings.items.ai': 'AI-помощник',
    'settings.items.notifications': 'Уведомления и звуки',
    'settings.items.privacy': 'Конфиденциальность',
    'settings.items.appearance': 'Оформление и язык',
    'settings.items.dataStorage': 'Данные и память',
    'settings.items.adminPanel': 'Админ-панель',
    // wallet settings
    'settings.wallet.balance': 'Баланс',
    'settings.wallet.topUp': 'Пополнить',
    'settings.wallet.methods': 'Способы оплаты',
    'settings.wallet.addMethod': 'Добавить способ',
    'settings.wallet.defaultCurrency': 'Валюта по умолчанию',
    'settings.wallet.paymentPin': 'PIN платежей',
    'settings.wallet.transactionHistory': 'История транзакций',
    'settings.wallet.limits': 'Лимиты',
    'settings.wallet.payout': 'Вывод средств',
    // messages settings
    'settings.messages.chatBackground': 'Фон чата',
    'settings.messages.textSize': 'Размер текста',
    'settings.messages.enterToSend': 'Enter для отправки',
    'settings.messages.autoDownload': 'Автозагрузка',
    'settings.messages.folders': 'Папки чатов',
    'settings.messages.savedMessages': 'Избранное',
    // video settings
    'settings.video.autoplay': 'Автовоспроизведение',
    'settings.video.quality': 'Качество',
    'settings.video.dataSaver': 'Экономия данных',
    // data storage
    'settings.data.storageUsage': 'Использование памяти',
    'settings.data.clearCache': 'Очистить кеш',
    'settings.data.messagesCache': 'Кеш сообщений',
    'settings.data.downloads': 'Загрузки',
    // history
    'history.paused': 'Запись истории приостановлена',
    'history.resumed': 'Запись истории возобновлена',
    'history.clearAll': 'Очистить всю историю',
    'history.clearConfirm': 'Удалить всю историю просмотров? Это действие нельзя отменить.',
    'history.cleared': 'История очищена',
    'pages.notifications': 'Уведомления',
    'pages.notificationsEmpty': 'Пока нет уведомлений',
    'pages.notificationsMarkAll': 'Прочитать все',
    'pages.videos': 'Видео', 'pages.channels': 'Каналы',
    'pages.admin': 'Админ-панель', 'pages.orders': 'Заказы',
    'pages.bookmarks': 'Сохранённые', 'pages.feed': 'Лента',
    'pages.stories': 'Истории', 'pages.followers': 'Подписчики',
    'pages.following': 'Подписки', 'pages.search': 'Поиск',
    'messages.newMessage': 'Новое сообщение', 'messages.noMessages': 'Нет сообщений',
    'messages.online': 'Онлайн', 'messages.typing': 'Печатает...',
    'messages.writeMessage': 'Напишите сообщение...',
    'messages.delivered': 'Доставлено', 'messages.seen': 'Прочитано',
    'post.like': 'Нравится', 'post.comment': 'Комментарий', 'post.share': 'Поделиться',
    'post.repost': 'Репост', 'post.save': 'Сохранить', 'post.report': 'Пожаловаться',
    'post.views': 'Просмотров', 'post.createCaption': 'О чём вы думаете?',
    'post.publishCta': 'Опубликовать', 'post.deleteConfirm': 'Удалить этот пост?',
    'report.title': 'Пожаловаться', 'report.subtitle': 'Выберите причину',
    'report.reasonSpam': 'Спам', 'report.reasonHarassment': 'Травля',
    'report.reasonHate': 'Язык вражды', 'report.reasonViolence': 'Насилие',
    'report.reasonNudity': 'Неподходящий контент', 'report.reasonScam': 'Мошенничество',
    'report.reasonOther': 'Другое', 'report.detailsHint': 'Доп. детали (необязательно)',
    'report.submit': 'Отправить', 'report.thanks': 'Жалоба принята, спасибо.',
    'videoEditor.title': 'Редактирование видео', 'videoEditor.trim': 'Обрезка',
    'videoEditor.crop': 'Кадрирование', 'videoEditor.filter': 'Фильтр',
    'videoEditor.music': 'Музыка', 'videoEditor.text': 'Текст',
    'videoEditor.export': 'Экспорт', 'videoEditor.savingDraft': 'Черновик сохранён',
    'story.create': 'Создать историю', 'story.addText': 'Добавить текст',
    'story.addSticker': 'Наклейка', 'story.addMusic': 'Музыка',
    'story.privacyEveryone': 'Все', 'story.privacyCloseFriends': 'Близкие друзья',
    'story.privacyOnlyMe': 'Только я',
    'a11y.openMenu': 'Открыть меню', 'a11y.closeMenu': 'Закрыть меню',
    'a11y.openProfile': 'Открыть профиль', 'a11y.likeButton': 'Кнопка "Нравится"',
    'a11y.commentButton': 'Кнопка "Комментарий"', 'a11y.shareButton': 'Кнопка "Поделиться"',
    'a11y.zoomIn': 'Приблизить', 'a11y.zoomOut': 'Отдалить',
  };
}
