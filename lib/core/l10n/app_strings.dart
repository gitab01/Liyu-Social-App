import 'package:flutter/widgets.dart';

/// Interface copy in English and Amharic.
///
/// Amharic is written in Ge'ez script, which renders left-to-right, so this
/// only needs a string table and an Ethiopic-capable font — not direction
/// flipping. `Noto Sans Ethiopic` ships on Android and `Kefa` on iOS; the web
/// build loads Noto Sans Ethiopic from the stylesheet in `web/index.html`.
class L10n {
  L10n(this.languageCode);

  final String languageCode;

  bool get isAmharic => languageCode == 'am';

  static L10n of(BuildContext context) {
    final locale = Localizations.localeOf(context);
    return L10n(locale.languageCode == 'am' ? 'am' : 'en');
  }

  String v(String key) => (isAmharic ? _am : _en)[key] ?? _en[key] ?? key;

  String get appName => 'Liyu';

  // Navigation
  String get home => v('home');
  String get search => v('search');
  String get create => v('create');
  String get inbox => v('inbox');
  String get notifications => v('notifications');
  String get profile => v('profile');

  // Feed
  String get feed => v('feed');
  String get stories => v('stories');
  String get comments => v('comments');
  String get like => v('like');
  String get liked => v('liked');
  String get addComment => v('addComment');
  String get writeAComment => v('writeAComment');
  String get noPostsYet => v('noPostsYet');
  String get nothingNewHere => v('nothingNewHere');
  String get loadingMore => v('loadingMore');
  String get endOfFeed => v('endOfFeed');
  String get pullToRefresh => v('pullToRefresh');
  String get showNewPosts => v('showNewPosts');
  String get reply => v('reply');
  String get share => v('share');
  String get copyLink => v('copyLink');
  String get delete => v('delete');
  String get report => v('report');
  String get block => v('block');
  String get blocked => v('blocked');
  String get unblock => v('unblock');
  String get postDeleted => v('postDeleted');

  // Composer
  String get newPost => v('newPost');
  String get newStory => v('newStory');
  String get whatsOnYourMind => v('whatsOnYourMind');
  String get addPhoto => v('addPhoto');
  String get camera => v('camera');
  String get gallery => v('gallery');
  String get audience => v('audience');
  String get everyone => v('everyone');
  String get followersOnly => v('followersOnly');
  String get publish => v('publish');
  String get publishing => v('publishing');
  String get compressing => v('compressing');
  String get uploading => v('uploading');
  String get savingData => v('savingData');
  String get postPublished => v('postPublished');
  String get queuedForSync => v('queuedForSync');

  // Stories
  String get yourStory => v('yourStory');
  String get tapToViewStory => v('tapToViewStory');
  String get storyExpired => v('storyExpired');
  String get timeLeft => v('timeLeft');
  String get viewedBy => v('viewedBy');
  String get noViewersYet => v('noViewersYet');

  // Chat
  String get messages => v('messages');
  String get typeAMessage => v('typeAMessage');
  String get send => v('send');
  String get pending => v('pending');
  String get sent => v('sent');
  String get failedToSend => v('failedToSend');
  String get retry => v('retry');
  String get noConversations => v('noConversations');
  String get startChat => v('startChat');
  String get unread => v('unread');

  // Profile
  String get posts => v('posts');
  String get followers => v('followers');
  String get following => v('following');
  String get follow => v('follow');
  String get followingShort => v('followingShort');
  String get editProfile => v('editProfile');
  String get message => v('message');
  String get aboutMe => v('aboutMe');
  String get displayName => v('displayName');
  String get save => v('save');
  String get suggestionsForYou => v('suggestionsForYou');
  String get people => v('people');

  // Auth
  String get signIn => v('signIn');
  String get signUp => v('signUp');
  String get signOut => v('signOut');
  String get phone => v('phone');
  String get email => v('email');
  String get password => v('password');
  String get continueWithPhone => v('continueWithPhone');
  String get enterCode => v('enterCode');
  String get codeSentTo => v('codeSentTo');
  String get devCodeHint => v('devCodeHint');
  String get verify => v('verify');
  String get welcomeToLiyu => v('welcomeToLiyu');
  String get signInSubtitle => v('signInSubtitle');
  String get createAccount => v('createAccount');
  String get orUseEmail => v('orUseEmail');

  // Settings + status
  String get settings => v('settings');
  String get markAllRead => v('markAllRead');
  String get language => v('language');
  String get english => v('english');
  String get amharic => v('amharic');
  String get theme => v('theme');
  String get light => v('light');
  String get dark => v('dark');
  String get system => v('system');
  String get offline => v('offline');
  String get offlineBanner => v('offlineBanner');
  String get simulateOffline => v('simulateOffline');
  String get backendLocal => v('backendLocal');
  String get backendFirebase => v('backendFirebase');
  String get backend => v('backend');
  String get account => v('account');
  String get dataSaver => v('dataSaver');
  String get dataSaverHint => v('dataSaverHint');

  // Errors
  String get somethingWentWrong => v('somethingWentWrong');
  String get permissionDenied => v('permissionDenied');
  String get tryAgain => v('tryAgain');
  String get cancel => v('cancel');
  String get required => v('required');
  String get invalidPhone => v('invalidPhone');
  String get invalidCode => v('invalidCode');

  static const Map<String, String> _en = {
    'home': 'Home',
    'search': 'Search',
    'create': 'Create',
    'inbox': 'Chats',
    'notifications': 'Notifications',
    'profile': 'Profile',
    'feed': 'Feed',
    'stories': 'Stories',
    'comments': 'Comments',
    'like': 'Like',
    'liked': 'Liked',
    'addComment': 'Add comment',
    'writeAComment': 'Write a comment…',
    'noPostsYet': 'No posts yet',
    'nothingNewHere': 'Nothing here yet',
    'loadingMore': 'Loading…',
    'endOfFeed': "You're all caught up",
    'pullToRefresh': 'Pull to refresh',
    'showNewPosts': 'Show new posts',
    'reply': 'Reply',
    'share': 'Share',
    'copyLink': 'Copy link',
    'delete': 'Delete',
    'report': 'Report',
    'block': 'Block',
    'blocked': 'Blocked',
    'unblock': 'Unblock',
    'postDeleted': 'Post deleted',
    'newPost': 'New post',
    'newStory': 'New story',
    'whatsOnYourMind': "What's on your mind?",
    'addPhoto': 'Add photo',
    'camera': 'Camera',
    'gallery': 'Gallery',
    'audience': 'Who can see this',
    'everyone': 'Everyone',
    'followersOnly': 'Followers only',
    'publish': 'Publish',
    'publishing': 'Publishing…',
    'compressing': 'Compressing…',
    'uploading': 'Uploading…',
    'savingData': 'Saved on data',
    'postPublished': 'Published',
    'queuedForSync': 'Saved offline — will publish when you reconnect',
    'yourStory': 'Your story',
    'tapToViewStory': 'Tap to view',
    'storyExpired': 'This story has expired',
    'timeLeft': 'left',
    'viewedBy': 'Viewed by',
    'noViewersYet': 'No views yet',
    'messages': 'Messages',
    'typeAMessage': 'Message…',
    'send': 'Send',
    'pending': 'Sending',
    'sent': 'Sent',
    'failedToSend': 'Not delivered',
    'retry': 'Retry',
    'noConversations': 'No conversations yet',
    'startChat': 'Start a chat',
    'unread': 'unread',
    'posts': 'Posts',
    'followers': 'Followers',
    'following': 'Following',
    'follow': 'Follow',
    'followingShort': 'Following',
    'editProfile': 'Edit profile',
    'message': 'Message',
    'aboutMe': 'About me',
    'displayName': 'Name',
    'save': 'Save',
    'suggestionsForYou': 'Suggested for you',
    'people': 'People',
    'signIn': 'Sign in',
    'signUp': 'Create account',
    'signOut': 'Sign out',
    'phone': 'Phone',
    'email': 'Email',
    'password': 'Password',
    'continueWithPhone': 'Continue with phone',
    'enterCode': 'Enter the code',
    'codeSentTo': 'Code sent to',
    'devCodeHint': 'Local backend: your code is',
    'verify': 'Verify',
    'welcomeToLiyu': 'Welcome to Liyu',
    'signInSubtitle': 'Stories, messages and photos that cost less data.',
    'createAccount': 'Create your account',
    'orUseEmail': 'Use email instead',
    'settings': 'Settings',
    'markAllRead': 'Mark all read',
    'language': 'Language',
    'english': 'English',
    'amharic': 'አማርኛ',
    'theme': 'Appearance',
    'light': 'Light',
    'dark': 'Dark',
    'system': 'System',
    'offline': 'Offline',
    'offlineBanner': 'Offline — changes are queued',
    'simulateOffline': 'Simulate offline',
    'backendLocal': 'Local backend (no credentials)',
    'backendFirebase': 'Firebase backend',
    'backend': 'Backend',
    'account': 'Account',
    'dataSaver': 'Data saver',
    'dataSaverHint': 'Load thumbnails only, and prefetch video on Wi-Fi.',
    'somethingWentWrong': 'Something went wrong',
    'permissionDenied': "You don't have access to this",
    'tryAgain': 'Try again',
    'cancel': 'Cancel',
    'required': 'Required',
    'invalidPhone': 'Enter a phone number with country code, like +2519…',
    'invalidCode': 'That code is not correct',
  };

  static const Map<String, String> _am = {
    'home': 'መነሻ',
    'search': 'ፈልግ',
    'create': 'ፍጠር',
    'inbox': 'ውይይቶች',
    'notifications': 'ማሳወቂያዎች',
    'profile': 'መገለጫ',
    'feed': 'መከታተያ',
    'stories': 'ታሪኮች',
    'comments': 'አስተያየቶች',
    'like': 'ወደድኩ',
    'liked': 'ወድደዋል',
    'addComment': 'አስተያየት ስጥ',
    'writeAComment': 'አስተያየት ይጻፉ…',
    'noPostsYet': 'እስካሁን ምንም ልጥፍ የለም',
    'nothingNewHere': 'እስካሁን ምንም የለም',
    'loadingMore': 'በመጫን ላይ…',
    'endOfFeed': 'ሁሉንም አየዋል',
    'pullToRefresh': 'ለማደስ ይጎትቱ',
    'showNewPosts': 'አዳዲስ ልጥፎችን አሳይ',
    'reply': 'መልስ',
    'share': 'ተካፈል',
    'copyLink': 'አገናኝ ቅዳ',
    'delete': 'አጥፋ',
    'report': 'ዘግብር',
    'block': 'አግድ',
    'blocked': 'ታግዷል',
    'unblock': 'አስወግድ ገደብ',
    'postDeleted': 'ልጥፉ ተሰርዟል',
    'newPost': 'አዲስ ልጥፍ',
    'newStory': 'አዲስ ታሪክ',
    'whatsOnYourMind': 'ምን እያሰቡ ነው?',
    'addPhoto': 'ፎቶ ጨምር',
    'camera': 'ካሜራ',
    'gallery': 'ጋለሪ',
    'audience': 'ማን ሊያየው ይችላል',
    'everyone': 'ሁሉም',
    'followersOnly': 'ተከታዮች ብቻ',
    'publish': 'ልጥፍ',
    'publishing': 'በመልክ ላይ…',
    'compressing': 'በማነክኪያ ላይ…',
    'uploading': 'በመስቀምጥ ላይ…',
    'savingData': 'በዳታ ቆጣቢ',
    'postPublished': 'ተለኳል',
    'queuedForSync': 'በመስመር ላይ ሳይሆን ተቀምጧል — ሲገናኙ ይለኳል',
    'yourStory': 'ታሪክዎ',
    'tapToViewStory': 'ለማየት ይንኩ',
    'storyExpired': 'ይህ ታሪክ ጊዜው አልፏል',
    'timeLeft': 'ቀርቷል',
    'viewedBy': 'ያዩት',
    'noViewersYet': 'እስካሁን የአይቶ የለም',
    'messages': 'መልእክቶች',
    'typeAMessage': 'መልእክት ይጻፉ…',
    'send': 'ላክ',
    'pending': 'በመላክ ላይ',
    'sent': 'ተልኳል',
    'failedToSend': 'አልተላከም',
    'retry': 'እንደገና ሞክር',
    'noConversations': 'እስካሁን ውይይት የለም',
    'startChat': 'ውይይት ጀምር',
    'unread': 'ያልተነበቡ',
    'posts': 'ልጥፎች',
    'followers': 'ተከታዮች',
    'following': 'የሚከተሉት',
    'follow': 'ተከተል',
    'followingShort': 'እየተከተሉ',
    'editProfile': 'መገለጫ አስተካክል',
    'message': 'መልእክት',
    'aboutMe': 'ስለ እኔ',
    'displayName': 'ስም',
    'save': 'አስቀምጥ',
    'suggestionsForYou': 'ለእርስዎ የተመረጡ',
    'people': 'ሰዎች',
    'signIn': 'ግባ',
    'signUp': 'መለያ ፍጠር',
    'signOut': 'ውጣ',
    'phone': 'ስልክ',
    'email': 'ኢሜይል',
    'password': 'የይለፍ ቃል',
    'continueWithPhone': 'በስልክ ቀጥል',
    'enterCode': 'ኮዱን ያስገቡ',
    'codeSentTo': 'ኮድ የተላከው',
    'devCodeHint': 'የአካባቢ ሰርገዋል፡ ኮድዎ',
    'verify': 'አረጋግጥ',
    'welcomeToLiyu': 'ለሊዩ እንኳን ደህና መጡ',
    'signInSubtitle': 'ታሪኮች፣ መልእክቶች እና ፎቶዎች — ያነሰ ዳታ የሚጠይቁ።',
    'createAccount': 'መለያዎን ይፍጠሩ',
    'orUseEmail': 'ኢሜይል ይጠቀሙ',
    'settings': 'ቅንብሮች',
    'markAllRead': 'ሁሉንም እንደተነበብ ምልክት አድርግ',
    'language': 'ቋንቋ',
    'english': 'English',
    'amharic': 'አማርኛ',
    'theme': 'መልክ',
    'light': 'ብሩህ',
    'dark': 'ጥላማ',
    'system': 'የስርዓቱ',
    'offline': 'ከመስመር ውጭ',
    'offlineBanner': 'ከመስመር ውጭ — ለውጦች ተሰማርተዋል',
    'simulateOffline': 'ከመስመር ውጭ ማስመሰል',
    'backendLocal': 'የአካባቢ ሰርቨር (ያለ ምስጢር)',
    'backendFirebase': 'Firebase ሰርቨር',
    'backend': 'ሰርቨር',
    'account': 'መለያ',
    'dataSaver': 'ዳታ ቆጣቢ',
    'dataSaverHint': 'ትንሽ ምስሎችን ብቻ አሳይ፣ ቪዲዮ በዋይፋይ ብቻ።',
    'somethingWentWrong': 'አንድ ነገር ተሳሳተ',
    'permissionDenied': 'የመግባት መብት የለዎትም',
    'tryAgain': 'ደግሞ ይሞክሩ',
    'cancel': 'ሰርዝ',
    'required': 'አስፈላጊ ነው',
    'invalidPhone': 'የስልክ ቁጥር ይጻፉ +2519…',
    'invalidCode': 'ኮዱ ትክክል አይደለም',
  };
}

/// Resolve interface copy for the ambient locale.
extension BuildContextL10n on BuildContext {
  L10n get t => L10n.of(this);
}
