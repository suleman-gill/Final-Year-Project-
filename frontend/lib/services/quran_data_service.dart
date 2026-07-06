import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';

// ═══════════════════════════════════════════════════════════
// MODELS
// ═══════════════════════════════════════════════════════════

enum WordStatus { pending, correct, incorrect }

/// Immutable word model.
/// Status is tracked separately as List<WordStatus> in RecitationScreen,
/// keeping the model pure and avoiding mutation of data objects.
class AyahWord {
  final String arabic;
  final String phonetic;
  final String tajweedTip;
  /// 1-based ayah number within the surah — real metadata, never inferred from text.
  final int ayahNumber;

  const AyahWord({
    required this.arabic,
    required this.phonetic,
    required this.tajweedTip,
    required this.ayahNumber,
  });
}

/// Typed ayah model — replaces Map<String, String> for type safety
/// and eliminates string-key lookup errors.
class Ayah {
  final String arabic;
  final String translation;

  const Ayah({required this.arabic, required this.translation});
}

class SurahInfo {
  final int number;
  final String nameArabic;
  final String nameEnglish;
  final String meaning;
  final int verses;
  final String revelationType;

  const SurahInfo({
    required this.number,
    required this.nameArabic,
    required this.nameEnglish,
    required this.meaning,
    required this.verses,
    required this.revelationType,
  });
}

// ═══════════════════════════════════════════════════════════
// SERVICE
// ═══════════════════════════════════════════════════════════
class QuranDataService {
  static final Dio _dio = Dio();

  /// Al-Fatiha words for recitation practice.
  /// Const — allocated once at compile time, never on the heap at runtime.
  static const List<AyahWord> fatihaWords = [
    AyahWord(arabic: 'بِسْمِ',        phonetic: 'bismi',       tajweedTip: 'Start with a soft "B" sound (kasra underneath).', ayahNumber: 1),
    AyahWord(arabic: 'ٱللَّهِ',       phonetic: 'allahi',      tajweedTip: 'Lam al-Jalalah — heavy "L" sound after fatha.',     ayahNumber: 1),
    AyahWord(arabic: 'ٱلرَّحْمَٰنِ',  phonetic: 'arrahmaani',  tajweedTip: 'Shaddah on "R". Stretch the "aa" for 2 counts.',    ayahNumber: 1),
    AyahWord(arabic: 'ٱلرَّحِيمِ',    phonetic: 'arrahiim',    tajweedTip: 'Stretch "ii" for 2 counts (natural madd).',          ayahNumber: 1),
    AyahWord(arabic: 'ٱلْحَمْدُ',     phonetic: 'alhamdu',     tajweedTip: '"Al" merges into "Ha". Begin directly with Hamdu.', ayahNumber: 2),
    AyahWord(arabic: 'لِلَّهِ',       phonetic: 'lillahi',     tajweedTip: 'Lam of Jalalah is heavy here (after kasra: light).', ayahNumber: 2),
    AyahWord(arabic: 'رَبِّ',         phonetic: 'rabbi',       tajweedTip: 'Shaddah on "B" — hold it for 2 counts.',             ayahNumber: 2),
    AyahWord(arabic: 'ٱلْعَٰلَمِينَ', phonetic: 'aalameen',    tajweedTip: 'Stretch "ee" for 2 counts. Clear "N" at end.',       ayahNumber: 2),
  ];

  /// Al-Fatiha typed ayahs for the Quran reader.
  static const List<Ayah> fatihaAyahs = [
    Ayah(
      arabic: 'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ',
      translation: 'In the name of Allah, the Most Gracious, the Most Merciful.',
    ),
    Ayah(
      arabic: 'ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَٰلَمِينَ',
      translation: 'All praise is due to Allah, Lord of all the worlds.',
    ),
    Ayah(
      arabic: 'ٱلرَّحْمَٰنِ ٱلرَّحِيمِ',
      translation: 'The Most Gracious, the Most Merciful.',
    ),
    Ayah(
      arabic: 'مَٰلِكِ يَوْمِ ٱلدِّينِ',
      translation: 'Master of the Day of Judgment.',
    ),
    Ayah(
      arabic: 'إِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينُ',
      translation: 'You alone we worship, and You alone we ask for help.',
    ),
    Ayah(
      arabic: 'ٱهْدِنَا ٱلصِّرَٰطَ ٱلْمُسْتَقِيمَ',
      translation: 'Guide us to the straight path.',
    ),
    Ayah(
      arabic: 'صِرَٰطَ ٱلَّذِينَ أَنْعَمْتَ عَلَيْهِمْ غَيْرِ ٱلْمَغْضُوبِ عَلَيْهِمْ وَلَا ٱلضَّآلِّينَ',
      translation: 'The path of those upon whom You have bestowed favor, '
          'not of those who have incurred anger, nor of those who have gone astray.',
    ),
  ];

  /// Surah index — abbreviated (add all 114 as needed for production).
  static const List<SurahInfo> surahs = [
    SurahInfo(number: 1, nameArabic: 'سُورَةُ ٱلْفَاتِحَةِ', nameEnglish: 'Al-Faatiha', meaning: 'The Opening', verses: 7, revelationType: 'Meccan'),
    SurahInfo(number: 2, nameArabic: 'سُورَةُ البَقَرَةِ', nameEnglish: 'Al-Baqara', meaning: 'The Cow', verses: 286, revelationType: 'Medinan'),
    SurahInfo(number: 3, nameArabic: 'سُورَةُ آلِ عِمۡرَانَ', nameEnglish: 'Aal-i-Imraan', meaning: 'The Family of Imraan', verses: 200, revelationType: 'Medinan'),
    SurahInfo(number: 4, nameArabic: 'سُورَةُ النِّسَاءِ', nameEnglish: 'An-Nisaa', meaning: 'The Women', verses: 176, revelationType: 'Medinan'),
    SurahInfo(number: 5, nameArabic: 'سُورَةُ المَائـِدَةِ', nameEnglish: 'Al-Maaida', meaning: 'The Table', verses: 120, revelationType: 'Medinan'),
    SurahInfo(number: 6, nameArabic: 'سُورَةُ الأَنۡعَامِ', nameEnglish: "Al-An'aam", meaning: 'The Cattle', verses: 165, revelationType: 'Meccan'),
    SurahInfo(number: 7, nameArabic: 'سُورَةُ الأَعۡرَافِ', nameEnglish: "Al-A'raaf", meaning: 'The Heights', verses: 206, revelationType: 'Meccan'),
    SurahInfo(number: 8, nameArabic: 'سُورَةُ الأَنفَالِ', nameEnglish: 'Al-Anfaal', meaning: 'The Spoils of War', verses: 75, revelationType: 'Medinan'),
    SurahInfo(number: 9, nameArabic: 'سُورَةُ التَّوۡبَةِ', nameEnglish: 'At-Tawba', meaning: 'The Repentance', verses: 129, revelationType: 'Medinan'),
    SurahInfo(number: 10, nameArabic: 'سُورَةُ يُونُسَ', nameEnglish: 'Yunus', meaning: 'Jonas', verses: 109, revelationType: 'Meccan'),
    SurahInfo(number: 11, nameArabic: 'سُورَةُ هُودٍ', nameEnglish: 'Hud', meaning: 'Hud', verses: 123, revelationType: 'Meccan'),
    SurahInfo(number: 12, nameArabic: 'سُورَةُ يُوسُفَ', nameEnglish: 'Yusuf', meaning: 'Joseph', verses: 111, revelationType: 'Meccan'),
    SurahInfo(number: 13, nameArabic: 'سُورَةُ الرَّعۡدِ', nameEnglish: "Ar-Ra'd", meaning: 'The Thunder', verses: 43, revelationType: 'Medinan'),
    SurahInfo(number: 14, nameArabic: 'سُورَةُ إِبۡرَاهِيمَ', nameEnglish: 'Ibrahim', meaning: 'Abraham', verses: 52, revelationType: 'Meccan'),
    SurahInfo(number: 15, nameArabic: 'سُورَةُ الحِجۡرِ', nameEnglish: 'Al-Hijr', meaning: 'The Rock', verses: 99, revelationType: 'Meccan'),
    SurahInfo(number: 16, nameArabic: 'سُورَةُ النَّحۡلِ', nameEnglish: 'An-Nahl', meaning: 'The Bee', verses: 128, revelationType: 'Meccan'),
    SurahInfo(number: 17, nameArabic: 'سُورَةُ الإِسۡرَاءِ', nameEnglish: 'Al-Israa', meaning: 'The Night Journey', verses: 111, revelationType: 'Meccan'),
    SurahInfo(number: 18, nameArabic: 'سُورَةُ الكَهۡفِ', nameEnglish: 'Al-Kahf', meaning: 'The Cave', verses: 110, revelationType: 'Meccan'),
    SurahInfo(number: 19, nameArabic: 'سُورَةُ مَرۡيَمَ', nameEnglish: 'Maryam', meaning: 'Mary', verses: 98, revelationType: 'Meccan'),
    SurahInfo(number: 20, nameArabic: 'سُورَةُ طه', nameEnglish: 'Taa-Haa', meaning: 'Taa-Haa', verses: 135, revelationType: 'Meccan'),
    SurahInfo(number: 21, nameArabic: 'سُورَةُ الأَنبِيَاءِ', nameEnglish: 'Al-Anbiyaa', meaning: 'The Prophets', verses: 112, revelationType: 'Meccan'),
    SurahInfo(number: 22, nameArabic: 'سُورَةُ الحَجِّ', nameEnglish: 'Al-Hajj', meaning: 'The Pilgrimage', verses: 78, revelationType: 'Medinan'),
    SurahInfo(number: 23, nameArabic: 'سُورَةُ المُؤۡمِنُونَ', nameEnglish: 'Al-Muminoon', meaning: 'The Believers', verses: 118, revelationType: 'Meccan'),
    SurahInfo(number: 24, nameArabic: 'سُورَةُ النُّورِ', nameEnglish: 'An-Noor', meaning: 'The Light', verses: 64, revelationType: 'Medinan'),
    SurahInfo(number: 25, nameArabic: 'سُورَةُ الفُرۡقَانِ', nameEnglish: 'Al-Furqaan', meaning: 'The Criterion', verses: 77, revelationType: 'Meccan'),
    SurahInfo(number: 26, nameArabic: 'سُورَةُ الشُّعَرَاءِ', nameEnglish: "Ash-Shu'araa", meaning: 'The Poets', verses: 227, revelationType: 'Meccan'),
    SurahInfo(number: 27, nameArabic: 'سُورَةُ النَّمۡلِ', nameEnglish: 'An-Naml', meaning: 'The Ant', verses: 93, revelationType: 'Meccan'),
    SurahInfo(number: 28, nameArabic: 'سُورَةُ القَصَصِ', nameEnglish: 'Al-Qasas', meaning: 'The Stories', verses: 88, revelationType: 'Meccan'),
    SurahInfo(number: 29, nameArabic: 'سُورَةُ العَنكَبُوتِ', nameEnglish: 'Al-Ankaboot', meaning: 'The Spider', verses: 69, revelationType: 'Meccan'),
    SurahInfo(number: 30, nameArabic: 'سُورَةُ الرُّومِ', nameEnglish: 'Ar-Room', meaning: 'The Romans', verses: 60, revelationType: 'Meccan'),
    SurahInfo(number: 31, nameArabic: 'سُورَةُ لُقۡمَانَ', nameEnglish: 'Luqman', meaning: 'Luqman', verses: 34, revelationType: 'Meccan'),
    SurahInfo(number: 32, nameArabic: 'سُورَةُ السَّجۡدَةِ', nameEnglish: 'As-Sajda', meaning: 'The Prostration', verses: 30, revelationType: 'Meccan'),
    SurahInfo(number: 33, nameArabic: 'سُورَةُ الأَحۡزَابِ', nameEnglish: 'Al-Ahzaab', meaning: 'The Clans', verses: 73, revelationType: 'Medinan'),
    SurahInfo(number: 34, nameArabic: 'سُورَةُ سَبَإٍ', nameEnglish: 'Saba', meaning: 'Sheba', verses: 54, revelationType: 'Meccan'),
    SurahInfo(number: 35, nameArabic: 'سُورَةُ فَاطِرٍ', nameEnglish: 'Faatir', meaning: 'The Originator', verses: 45, revelationType: 'Meccan'),
    SurahInfo(number: 36, nameArabic: 'سُورَةُ يسٓ', nameEnglish: 'Yaseen', meaning: 'Yaseen', verses: 83, revelationType: 'Meccan'),
    SurahInfo(number: 37, nameArabic: 'سُورَةُ الصَّافَّاتِ', nameEnglish: 'As-Saaffaat', meaning: 'Those drawn up in Ranks', verses: 182, revelationType: 'Meccan'),
    SurahInfo(number: 38, nameArabic: 'سُورَةُ صٓ', nameEnglish: 'Saad', meaning: 'The letter Saad', verses: 88, revelationType: 'Meccan'),
    SurahInfo(number: 39, nameArabic: 'سُورَةُ الزُّمَرِ', nameEnglish: 'Az-Zumar', meaning: 'The Groups', verses: 75, revelationType: 'Meccan'),
    SurahInfo(number: 40, nameArabic: 'سُورَةُ غَافِرٍ', nameEnglish: 'Ghafir', meaning: 'The Forgiver', verses: 85, revelationType: 'Meccan'),
    SurahInfo(number: 41, nameArabic: 'سُورَةُ فُصِّلَتۡ', nameEnglish: 'Fussilat', meaning: 'Explained in detail', verses: 54, revelationType: 'Meccan'),
    SurahInfo(number: 42, nameArabic: 'سُورَةُ الشُّورَىٰ', nameEnglish: 'Ash-Shura', meaning: 'Consultation', verses: 53, revelationType: 'Meccan'),
    SurahInfo(number: 43, nameArabic: 'سُورَةُ الزُّخۡرُفِ', nameEnglish: 'Az-Zukhruf', meaning: 'Ornaments of gold', verses: 89, revelationType: 'Meccan'),
    SurahInfo(number: 44, nameArabic: 'سُورَةُ الدُّخَانِ', nameEnglish: 'Ad-Dukhaan', meaning: 'The Smoke', verses: 59, revelationType: 'Meccan'),
    SurahInfo(number: 45, nameArabic: 'سُورَةُ الجَاثِيَةِ', nameEnglish: 'Al-Jaathiya', meaning: 'Crouching', verses: 37, revelationType: 'Meccan'),
    SurahInfo(number: 46, nameArabic: 'سُورَةُ الأَحۡقَافِ', nameEnglish: 'Al-Ahqaf', meaning: 'The Dunes', verses: 35, revelationType: 'Meccan'),
    SurahInfo(number: 47, nameArabic: 'سُورَةُ مُحَمَّدٍ', nameEnglish: 'Muhammad', meaning: 'Muhammad', verses: 38, revelationType: 'Medinan'),
    SurahInfo(number: 48, nameArabic: 'سُورَةُ الفَتۡحِ', nameEnglish: 'Al-Fath', meaning: 'The Victory', verses: 29, revelationType: 'Medinan'),
    SurahInfo(number: 49, nameArabic: 'سُورَةُ الحُجُرَاتِ', nameEnglish: 'Al-Hujuraat', meaning: 'The Inner Apartments', verses: 18, revelationType: 'Medinan'),
    SurahInfo(number: 50, nameArabic: 'سُورَةُ قٓ', nameEnglish: 'Qaaf', meaning: 'The letter Qaaf', verses: 45, revelationType: 'Meccan'),
    SurahInfo(number: 51, nameArabic: 'سُورَةُ الذَّارِيَاتِ', nameEnglish: 'Adh-Dhaariyat', meaning: 'The Winnowing Winds', verses: 60, revelationType: 'Meccan'),
    SurahInfo(number: 52, nameArabic: 'سُورَةُ الطُّورِ', nameEnglish: 'At-Tur', meaning: 'The Mount', verses: 49, revelationType: 'Meccan'),
    SurahInfo(number: 53, nameArabic: 'سُورَةُ النَّجۡمِ', nameEnglish: 'An-Najm', meaning: 'The Star', verses: 62, revelationType: 'Meccan'),
    SurahInfo(number: 54, nameArabic: 'سُورَةُ القَمَرِ', nameEnglish: 'Al-Qamar', meaning: 'The Moon', verses: 55, revelationType: 'Meccan'),
    SurahInfo(number: 55, nameArabic: 'سُورَةُ الرَّحۡمَٰن', nameEnglish: 'Ar-Rahmaan', meaning: 'The Beneficent', verses: 78, revelationType: 'Medinan'),
    SurahInfo(number: 56, nameArabic: 'سُورَةُ الوَاقِعَةِ', nameEnglish: 'Al-Waaqia', meaning: 'The Inevitable', verses: 96, revelationType: 'Meccan'),
    SurahInfo(number: 57, nameArabic: 'سُورَةُ الحَدِيدِ', nameEnglish: 'Al-Hadid', meaning: 'The Iron', verses: 29, revelationType: 'Medinan'),
    SurahInfo(number: 58, nameArabic: 'سُورَةُ المُجَادلَةِ', nameEnglish: 'Al-Mujaadila', meaning: 'The Pleading Woman', verses: 22, revelationType: 'Medinan'),
    SurahInfo(number: 59, nameArabic: 'سُورَةُ الحَشۡرِ', nameEnglish: 'Al-Hashr', meaning: 'The Exile', verses: 24, revelationType: 'Medinan'),
    SurahInfo(number: 60, nameArabic: 'سُورَةُ المُمۡتَحنَةِ', nameEnglish: 'Al-Mumtahana', meaning: 'She that is to be examined', verses: 13, revelationType: 'Medinan'),
    SurahInfo(number: 61, nameArabic: 'سُورَةُ الصَّفِّ', nameEnglish: 'As-Saff', meaning: 'The Ranks', verses: 14, revelationType: 'Medinan'),
    SurahInfo(number: 62, nameArabic: 'سُورَةُ الجُمُعَةِ', nameEnglish: "Al-Jumu'a", meaning: 'Friday', verses: 11, revelationType: 'Medinan'),
    SurahInfo(number: 63, nameArabic: 'سُورَةُ المُنَافِقُونَ', nameEnglish: 'Al-Munaafiqoon', meaning: 'The Hypocrites', verses: 11, revelationType: 'Medinan'),
    SurahInfo(number: 64, nameArabic: 'سُورَةُ التَّغَابُنِ', nameEnglish: 'At-Taghaabun', meaning: 'Mutual Disillusion', verses: 18, revelationType: 'Medinan'),
    SurahInfo(number: 65, nameArabic: 'سُورَةُ الطَّلَاقِ', nameEnglish: 'At-Talaaq', meaning: 'Divorce', verses: 12, revelationType: 'Medinan'),
    SurahInfo(number: 66, nameArabic: 'سُورَةُ التَّحۡرِيمِ', nameEnglish: 'At-Tahrim', meaning: 'The Prohibition', verses: 12, revelationType: 'Medinan'),
    SurahInfo(number: 67, nameArabic: 'سُورَةُ المُلۡكِ', nameEnglish: 'Al-Mulk', meaning: 'The Sovereignty', verses: 30, revelationType: 'Meccan'),
    SurahInfo(number: 68, nameArabic: 'سُورَةُ القَلَمِ', nameEnglish: 'Al-Qalam', meaning: 'The Pen', verses: 52, revelationType: 'Meccan'),
    SurahInfo(number: 69, nameArabic: 'سُورَةُ الحَاقَّةِ', nameEnglish: 'Al-Haaqqa', meaning: 'The Reality', verses: 52, revelationType: 'Meccan'),
    SurahInfo(number: 70, nameArabic: 'سُورَةُ المَعَارِجِ', nameEnglish: "Al-Ma'aarij", meaning: 'The Ascending Stairways', verses: 44, revelationType: 'Meccan'),
    SurahInfo(number: 71, nameArabic: 'سُورَةُ نُوحٍ', nameEnglish: 'Nooh', meaning: 'Noah', verses: 28, revelationType: 'Meccan'),
    SurahInfo(number: 72, nameArabic: 'سُورَةُ الجِنِّ', nameEnglish: 'Al-Jinn', meaning: 'The Jinn', verses: 28, revelationType: 'Meccan'),
    SurahInfo(number: 73, nameArabic: 'سُورَةُ المُزَّمِّلِ', nameEnglish: 'Al-Muzzammil', meaning: 'The Enshrouded One', verses: 20, revelationType: 'Meccan'),
    SurahInfo(number: 74, nameArabic: 'سُورَةُ المُدَّثِّرِ', nameEnglish: 'Al-Muddaththir', meaning: 'The Cloaked One', verses: 56, revelationType: 'Meccan'),
    SurahInfo(number: 75, nameArabic: 'سُورَةُ القِيَامَةِ', nameEnglish: 'Al-Qiyaama', meaning: 'The Resurrection', verses: 40, revelationType: 'Meccan'),
    SurahInfo(number: 76, nameArabic: 'سُورَةُ الإِنسَانِ', nameEnglish: 'Al-Insaan', meaning: 'Man', verses: 31, revelationType: 'Medinan'),
    SurahInfo(number: 77, nameArabic: 'سُورَةُ المُرۡسَلَاتِ', nameEnglish: 'Al-Mursalaat', meaning: 'The Emissaries', verses: 50, revelationType: 'Meccan'),
    SurahInfo(number: 78, nameArabic: 'سُورَةُ النَّبَإِ', nameEnglish: 'An-Naba', meaning: 'The Announcement', verses: 40, revelationType: 'Meccan'),
    SurahInfo(number: 79, nameArabic: 'سُورَةُ النَّازِعَاتِ', nameEnglish: "An-Naazi'aat", meaning: 'Those who drag forth', verses: 46, revelationType: 'Meccan'),
    SurahInfo(number: 80, nameArabic: 'سُورَةُ عَبَسَ', nameEnglish: 'Abasa', meaning: 'He frowned', verses: 42, revelationType: 'Meccan'),
    SurahInfo(number: 81, nameArabic: 'سُورَةُ التَّكۡوِيرِ', nameEnglish: 'At-Takwir', meaning: 'The Overthrowing', verses: 29, revelationType: 'Meccan'),
    SurahInfo(number: 82, nameArabic: 'سُورَةُ الانفِطَارِ', nameEnglish: 'Al-Infitaar', meaning: 'The Cleaving', verses: 19, revelationType: 'Meccan'),
    SurahInfo(number: 83, nameArabic: 'سُورَةُ المُطَفِّفِينَ', nameEnglish: 'Al-Mutaffifin', meaning: 'Defrauding', verses: 36, revelationType: 'Meccan'),
    SurahInfo(number: 84, nameArabic: 'سُورَةُ الانشِقَاقِ', nameEnglish: 'Al-Inshiqaaq', meaning: 'The Splitting Open', verses: 25, revelationType: 'Meccan'),
    SurahInfo(number: 85, nameArabic: 'سُورَةُ البُرُوجِ', nameEnglish: 'Al-Burooj', meaning: 'The Constellations', verses: 22, revelationType: 'Meccan'),
    SurahInfo(number: 86, nameArabic: 'سُورَةُ الطَّارِقِ', nameEnglish: 'At-Taariq', meaning: 'The Morning Star', verses: 17, revelationType: 'Meccan'),
    SurahInfo(number: 87, nameArabic: 'سُورَةُ الأَعۡلَىٰ', nameEnglish: "Al-A'laa", meaning: 'The Most High', verses: 19, revelationType: 'Meccan'),
    SurahInfo(number: 88, nameArabic: 'سُورَةُ الغَاشِيَةِ', nameEnglish: 'Al-Ghaashiya', meaning: 'The Overwhelming', verses: 26, revelationType: 'Meccan'),
    SurahInfo(number: 89, nameArabic: 'سُورَةُ الفَجۡرِ', nameEnglish: 'Al-Fajr', meaning: 'The Dawn', verses: 30, revelationType: 'Meccan'),
    SurahInfo(number: 90, nameArabic: 'سُورَةُ البَلَدِ', nameEnglish: 'Al-Balad', meaning: 'The City', verses: 20, revelationType: 'Meccan'),
    SurahInfo(number: 91, nameArabic: 'سُورَةُ الشَّمۡسِ', nameEnglish: 'Ash-Shams', meaning: 'The Sun', verses: 15, revelationType: 'Meccan'),
    SurahInfo(number: 92, nameArabic: 'سُورَةُ اللَّيۡلِ', nameEnglish: 'Al-Lail', meaning: 'The Night', verses: 21, revelationType: 'Meccan'),
    SurahInfo(number: 93, nameArabic: 'سُورَةُ الضُّحَىٰ', nameEnglish: 'Ad-Dhuhaa', meaning: 'The Morning Hours', verses: 11, revelationType: 'Meccan'),
    SurahInfo(number: 94, nameArabic: 'سُورَةُ الشَّرۡحِ', nameEnglish: 'Ash-Sharh', meaning: 'The Consolation', verses: 8, revelationType: 'Meccan'),
    SurahInfo(number: 95, nameArabic: 'سُورَةُ التِّينِ', nameEnglish: 'At-Tin', meaning: 'The Fig', verses: 8, revelationType: 'Meccan'),
    SurahInfo(number: 96, nameArabic: 'سُورَةُ العَلَقِ', nameEnglish: 'Al-Alaq', meaning: 'The Clot', verses: 19, revelationType: 'Meccan'),
    SurahInfo(number: 97, nameArabic: 'سُورَةُ القَدۡرِ', nameEnglish: 'Al-Qadr', meaning: 'The Power, Fate', verses: 5, revelationType: 'Meccan'),
    SurahInfo(number: 98, nameArabic: 'سُورَةُ البَيِّنَةِ', nameEnglish: 'Al-Bayyina', meaning: 'The Evidence', verses: 8, revelationType: 'Medinan'),
    SurahInfo(number: 99, nameArabic: 'سُورَةُ الزَّلۡزَلَةِ', nameEnglish: 'Az-Zalzala', meaning: 'The Earthquake', verses: 8, revelationType: 'Medinan'),
    SurahInfo(number: 100, nameArabic: 'سُورَةُ العَادِيَاتِ', nameEnglish: 'Al-Aadiyaat', meaning: 'The Chargers', verses: 11, revelationType: 'Meccan'),
    SurahInfo(number: 101, nameArabic: 'سُورَةُ القَارِعَةِ', nameEnglish: "Al-Qaari'a", meaning: 'The Calamity', verses: 11, revelationType: 'Meccan'),
    SurahInfo(number: 102, nameArabic: 'سُورَةُ التَّكَاثُرِ', nameEnglish: 'At-Takaathur', meaning: 'Competition', verses: 8, revelationType: 'Meccan'),
    SurahInfo(number: 103, nameArabic: 'سُورَةُ العَصۡرِ', nameEnglish: 'Al-Asr', meaning: 'The Declining Day, Epoch', verses: 3, revelationType: 'Meccan'),
    SurahInfo(number: 104, nameArabic: 'سُورَةُ الهُمَزَةِ', nameEnglish: 'Al-Humaza', meaning: 'The Traducer', verses: 9, revelationType: 'Meccan'),
    SurahInfo(number: 105, nameArabic: 'سُورَةُ الفِيلِ', nameEnglish: 'Al-Fil', meaning: 'The Elephant', verses: 5, revelationType: 'Meccan'),
    SurahInfo(number: 106, nameArabic: 'سُورَةُ قُرَيۡشٍ', nameEnglish: 'Quraish', meaning: 'Quraysh', verses: 4, revelationType: 'Meccan'),
    SurahInfo(number: 107, nameArabic: 'سُورَةُ المَاعُونِ', nameEnglish: "Al-Maa'un", meaning: 'Almsgiving', verses: 7, revelationType: 'Meccan'),
    SurahInfo(number: 108, nameArabic: 'سُورَةُ الكَوۡثَرِ', nameEnglish: 'Al-Kawthar', meaning: 'Abundance', verses: 3, revelationType: 'Meccan'),
    SurahInfo(number: 109, nameArabic: 'سُورَةُ الكَافِرُونَ', nameEnglish: 'Al-Kaafiroon', meaning: 'The Disbelievers', verses: 6, revelationType: 'Meccan'),
    SurahInfo(number: 110, nameArabic: 'سُورَةُ النَّصۡرِ', nameEnglish: 'An-Nasr', meaning: 'Divine Support', verses: 3, revelationType: 'Medinan'),
    SurahInfo(number: 111, nameArabic: 'سُورَةُ المَسَدِ', nameEnglish: 'Al-Masad', meaning: 'The Palm Fibre', verses: 5, revelationType: 'Meccan'),
    SurahInfo(number: 112, nameArabic: 'سُورَةُ الإِخۡلَاصِ', nameEnglish: 'Al-Ikhlaas', meaning: 'Sincerity', verses: 4, revelationType: 'Meccan'),
    SurahInfo(number: 113, nameArabic: 'سُورَةُ الفَلَقِ', nameEnglish: 'Al-Falaq', meaning: 'The Dawn', verses: 5, revelationType: 'Meccan'),
    SurahInfo(number: 114, nameArabic: 'سُورَةُ النَّاسِ', nameEnglish: 'An-Naas', meaning: 'Mankind', verses: 6, revelationType: 'Meccan'),
  ];


  /// O(1) surah lookup by number.
  /// Built once as a final field — never rebuilt during the app lifetime.
  /// Complexity: O(n) build once → O(1) every lookup thereafter.
  static final Map<int, SurahInfo> surahMap = {
    for (final s in surahs) s.number: s,
  };

  /// Returns the ayahs for a given surah number.
  static List<Ayah> getAyahs(int surahNumber) {
    if (_ayahCache.containsKey(surahNumber)) {
      return _ayahCache[surahNumber]!;
    }
    return fatihaAyahs;
  }

  static String _toArabicNumerals(int number) {
    const english = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const arabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    String result = number.toString();
    for (int i = 0; i < english.length; i++) {
      result = result.replaceAll(english[i], arabic[i]);
    }
    return result;
  }

  static final Map<int, List<Ayah>> _ayahCache = {};
  static final Map<int, List<AyahWord>> _wordCache = {};
  static bool _isInitialized = false;
  static bool get isInitialized => _isInitialized;
  static Future<void>? _initFuture;

  static Future<void> ensureInitialized() async {
    if (_isInitialized) return;
    _initFuture ??= _initializeInternal();
    await _initFuture;
  }

  static Future<void> _initializeInternal() async {
    try {
      final jsonString = await rootBundle.loadString('assets/quran_complete.json');
      final parsed = await compute(_parseJson, jsonString);
      final surahsList = parsed['surahs'] as List;
      for (final surahJson in surahsList) {
        final surahNum = surahJson['number'] as int;
        final ayahsJson = surahJson['ayahs'] as List;
        final List<Ayah> ayahs = [];
        final List<AyahWord> words = [];
        for (int i = 0; i < ayahsJson.length; i++) {
          final ayahJson = ayahsJson[i];
          var arabic = (ayahJson['text'] as String).trim();
          final translation = (ayahJson['translation'] as String).trim();
          final numberInSurah = ayahJson['numberInSurah'] as int;

          // Strip Bismillah prefix if not Surah 1 or 9
          if (i == 0 && surahNum > 1 && surahNum != 9) {
            if (arabic.startsWith('بِسْمِ')) {
              final parts = arabic.split(RegExp(r'\s+'));
              if (parts.length >= 4) {
                arabic = parts.sublist(4).join(' ');
              }
            }
          }

          ayahs.add(Ayah(arabic: arabic, translation: translation));

          final wordStrings = arabic.trim().split(RegExp(r'\s+'));
          for (final w in wordStrings) {
            if (w.isNotEmpty) {
              words.add(AyahWord(
                arabic: w,
                phonetic: '...',
                tajweedTip: 'Follow standard Tajweed rules',
                ayahNumber: numberInSurah,
              ));
            }
          }
        }
        _ayahCache[surahNum] = ayahs;
        _wordCache[surahNum] = words;
      }
      _isInitialized = true;
    } catch (e) {
      print('QuranDataService offline init error: $e');
    }
  }

  /// Fetches ayahs (arabic + translation) for a surah.
  /// Used by Reader, Recitation, and Results screens for page grouping.
  static Future<List<Ayah>> fetchSurahAyahs(int surahNum) async {
    await ensureInitialized();
    if (_ayahCache.containsKey(surahNum)) return _ayahCache[surahNum]!;
    return surahNum == 1 ? fatihaAyahs : fatihaAyahs;
  }

  static Future<List<AyahWord>> fetchSurahWords(int surahNum) async {
    await ensureInitialized();
    if (_wordCache.containsKey(surahNum)) {
      return _wordCache[surahNum]!;
    }
    return fatihaWords;
  }

  /// Fetches Ayah text and splits it into AyahWords.
  static Future<List<AyahWord>> fetchAyahWords(int surahNum, int ayahNum) async {
    await ensureInitialized();
    if (_wordCache.containsKey(surahNum)) {
      final surahWords = _wordCache[surahNum]!;
      return surahWords.where((w) => w.ayahNumber == ayahNum).toList();
    }
    return fatihaWords;
  }

  /// Groups a flat list of [Ayah]s into ~65-word Mushaf pages.
  static List<List<Ayah>> groupAyahsIntoPages(List<Ayah> ayahs) {
    final List<List<Ayah>> pages = [];
    List<Ayah> currentPage = [];
    int wordCount = 0;
    for (final ayah in ayahs) {
      final wc = ayah.arabic.split(RegExp(r'\s+')).length;
      if (wordCount + wc > 65 && currentPage.isNotEmpty) {
        pages.add(currentPage);
        currentPage = [ayah];
        wordCount = wc;
      } else {
        currentPage.add(ayah);
        wordCount += wc;
      }
    }
    if (currentPage.isNotEmpty) pages.add(currentPage);
    return pages.isEmpty ? [[]] : pages;
  }
}

Map<String, dynamic> _parseJson(String jsonString) {
  return jsonDecode(jsonString) as Map<String, dynamic>;
}
