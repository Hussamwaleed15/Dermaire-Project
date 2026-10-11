import 'package:flutter/widgets.dart';
import '../capture/photo_disclosure.dart';

/// Entry copy only; no interpretation of server account or consent states.
class EntryCopy {
  EntryCopy.of(BuildContext context)
    : arabic = Localizations.localeOf(context).languageCode == 'ar';
  final bool arabic;
  String choose(String en, String ar) => arabic ? ar : en;
  String error(String value) =>
      !arabic || RegExp(r'[\u0600-\u06FF]').hasMatch(value)
      ? value
      : _errors[value] ??
            'تعذّر إكمال هذه الخطوة. تحقّق من اتصالك وأعد المحاولة، أو سجّل الدخول مجددًا.';
  static const _errors = <String, String>{
    'Your session changed or expired. Please sign in again.':
        'تغيّرت جلستك أو انتهت صلاحيتها. سجّل الدخول مجددًا.',
    'Please sign in again.': 'يرجى تسجيل الدخول مجددًا.',
    'The server has not confirmed your acceptance. Please retry.':
        'لم يؤكّد السيرفر تسجيل موافقتك. أعد المحاولة.',
    'Safety acceptance could not be confirmed in time. Please retry.':
        'انتهت مهلة تأكيد موافقة السلامة. أعد المحاولة.',
    'Could not confirm safety acceptance. Check your connection and retry.':
        'تعذّر تأكيد موافقة السلامة. تحقّق من اتصالك وأعد المحاولة.',
    'Safety acceptance access was denied. Retry or sign in again.':
        'تم رفض الوصول لتأكيد موافقة السلامة. أعد المحاولة أو سجّل الدخول مجددًا.',
    'Safety acceptance is unavailable. Please retry.':
        'تأكيد موافقة السلامة غير متاح حاليًا. أعد المحاولة.',
    'Safety acceptance could not be verified. Please retry.':
        'تعذّر التحقق من موافقة السلامة. أعد المحاولة.',
    'Account profile could not be verified. Please retry.':
        'تعذّر التحقق من ملف الحساب. أعد المحاولة.',
    'Account profile is unavailable. Please retry.':
        'ملف الحساب غير متاح حاليًا. أعد المحاولة.',
    'Profile access was denied. Retry or sign in again.':
        'تم رفض الوصول لملف الحساب. أعد المحاولة أو سجّل الدخول مجددًا.',
    'Profile loading timed out. Please retry.':
        'انتهت مهلة تحميل ملف الحساب. أعد المحاولة.',
    'Could not load your account profile. Check your connection and retry.':
        'تعذّر تحميل ملف الحساب. تحقّق من اتصالك وأعد المحاولة.',
    'Email already registered': 'هذا البريد الإلكتروني مسجّل بالفعل.',
  };
  String get welcome =>
      choose('A clearer view of your skin.', 'صورة أوضح لبشرتك.');
  String get welcomeBody => choose(
    'Observe changes. Understand your history. Take the next step with more context.',
    'لاحظ التغيّرات. افهم تاريخ بشرتك. وخُذ خطوتك التالية بمعلومات أوضح.',
  );
  String get create => choose('Create account', 'إنشاء حساب');
  String get existing =>
      choose('I already have an account', 'لديّ حساب بالفعل');
  String get email => choose('Email', 'البريد الإلكتروني');
  String get password => choose('Password', 'كلمة المرور');
  String get confirm => choose('Confirm password', 'تأكيد كلمة المرور');
  String get signIn => choose('Sign in', 'تسجيل الدخول');
  String get google =>
      choose('Continue with Google', 'المتابعة باستخدام Google');
  String get retry => choose('Try again', 'حاول مجددًا');
  String get signOut => choose(
    'Sign out / use another account',
    'تسجيل الخروج / استخدام حساب آخر',
  );
  String get checking => choose(
    'Confirming your safety acceptance…',
    'جارٍ التحقق من موافقتك على إرشادات السلامة…',
  );
  String get profile =>
      choose('Loading your account profile…', 'جارٍ تحميل ملف حسابك…');
  String get signingIn => choose('Signing you in…', 'جارٍ تسجيل الدخول…');
  String get failure =>
      choose('We couldn’t complete this step', 'لم نتمكن من إكمال هذه الخطوة');
  String get authError => choose(
    'Sign-in failed: please check your details and connection, then try again.',
    'تعذّر تسجيل الدخول. تحقّق من بياناتك واتصالك ثم حاول مجددًا.',
  );
  String get success => choose('You’re ready to continue', 'أنت جاهز للمتابعة');
  String get continueApp =>
      choose('Continue to Dermaire', 'المتابعة إلى Dermaire');
  String get clinicalDisclaimer => choose(
    'Sign-in confirmation is not a clinical assessment.',
    'تأكيد تسجيل الدخول ليس تقييمًا طبيًا.',
  );
  String get disclosure => choose(
    photoUploadDisclosure,
    'اختيار صورة يرفعها بأمان إلى Dermaire لفحص الجودة وتقديم تقديرات محتملة للصورة. تُخزَّن الصور المقبولة في مساحة خاصة على Azure Blob Storage عند توفر التخزين. تُحذف الصور المخزنة عند اكتمال حذف حسابك.',
  );
  String get validEmail =>
      choose('Enter a valid email address', 'أدخل بريدًا إلكترونيًا صالحًا');
  String get passwordRequired =>
      choose('Enter your password', 'أدخل كلمة المرور');
  String get passwordRules => choose(
    'Use 8+ characters with upper, lower and a number',
    'استخدم ٨ أحرف أو أكثر مع أحرف كبيرة وصغيرة ورقم',
  );
}
