/// Languages offered in the picker (YouTube caption / translation codes).
library;

/// One caption language with its name in each app language. These names are
/// the only screen text kept outside the translation files: the list is data
/// (113 YouTube codes), and both names sit side by side so none is missing.
class Language {
  const Language(this.code, this.pt, this.en);
  final String code;

  /// Name in Portuguese, e.g. "Inglês".
  final String pt;

  /// Name in English, e.g. "English".
  final String en;

  /// Name in the app language [appLanguage] ("pt" or "en").
  String nameIn(String appLanguage) => appLanguage == 'pt' ? pt : en;
}

const languages = <Language>[
  Language('en', 'Inglês', 'English'),
  Language('pt', 'Português', 'Portuguese'),
  Language('pt-BR', 'Português (Brasil)', 'Portuguese (Brazil)'),
  Language('pt-PT', 'Português (Portugal)', 'Portuguese (Portugal)'),
  Language('es', 'Espanhol', 'Spanish'),
  Language('es-419', 'Espanhol (América Latina)', 'Spanish (Latin America)'),
  Language('fr', 'Francês', 'French'),
  Language('de', 'Alemão', 'German'),
  Language('it', 'Italiano', 'Italian'),
  Language('nl', 'Holandês', 'Dutch'),
  Language('ja', 'Japonês', 'Japanese'),
  Language('ko', 'Coreano', 'Korean'),
  Language('zh-Hans', 'Chinês (simplificado)', 'Chinese (Simplified)'),
  Language('zh-Hant', 'Chinês (tradicional)', 'Chinese (Traditional)'),
  Language('ru', 'Russo', 'Russian'),
  Language('uk', 'Ucraniano', 'Ukrainian'),
  Language('pl', 'Polonês', 'Polish'),
  Language('tr', 'Turco', 'Turkish'),
  Language('ar', 'Árabe', 'Arabic'),
  Language('hi', 'Hindi', 'Hindi'),
  Language('bn', 'Bengali', 'Bengali'),
  Language('id', 'Indonésio', 'Indonesian'),
  Language('ms', 'Malaio', 'Malay'),
  Language('vi', 'Vietnamita', 'Vietnamese'),
  Language('th', 'Tailandês', 'Thai'),
  Language('fil', 'Filipino', 'Filipino'),
  Language('he', 'Hebraico', 'Hebrew'),
  Language('fa', 'Persa', 'Persian'),
  Language('ur', 'Urdu', 'Urdu'),
  Language('sv', 'Sueco', 'Swedish'),
  Language('no', 'Norueguês', 'Norwegian'),
  Language('da', 'Dinamarquês', 'Danish'),
  Language('fi', 'Finlandês', 'Finnish'),
  Language('is', 'Islandês', 'Icelandic'),
  Language('cs', 'Tcheco', 'Czech'),
  Language('sk', 'Eslovaco', 'Slovak'),
  Language('hu', 'Húngaro', 'Hungarian'),
  Language('ro', 'Romeno', 'Romanian'),
  Language('bg', 'Búlgaro', 'Bulgarian'),
  Language('el', 'Grego', 'Greek'),
  Language('sr', 'Sérvio', 'Serbian'),
  Language('hr', 'Croata', 'Croatian'),
  Language('bs', 'Bósnio', 'Bosnian'),
  Language('sl', 'Esloveno', 'Slovenian'),
  Language('mk', 'Macedônio', 'Macedonian'),
  Language('sq', 'Albanês', 'Albanian'),
  Language('lt', 'Lituano', 'Lithuanian'),
  Language('lv', 'Letão', 'Latvian'),
  Language('et', 'Estoniano', 'Estonian'),
  Language('be', 'Bielorrusso', 'Belarusian'),
  Language('ka', 'Georgiano', 'Georgian'),
  Language('hy', 'Armênio', 'Armenian'),
  Language('az', 'Azerbaijano', 'Azerbaijani'),
  Language('kk', 'Cazaque', 'Kazakh'),
  Language('uz', 'Uzbeque', 'Uzbek'),
  Language('ky', 'Quirguiz', 'Kyrgyz'),
  Language('tg', 'Tadjique', 'Tajik'),
  Language('mn', 'Mongol', 'Mongolian'),
  Language('ca', 'Catalão', 'Catalan'),
  Language('eu', 'Basco', 'Basque'),
  Language('gl', 'Galego', 'Galician'),
  Language('cy', 'Galês', 'Welsh'),
  Language('ga', 'Irlandês', 'Irish'),
  Language('gd', 'Gaélico escocês', 'Scottish Gaelic'),
  Language('mt', 'Maltês', 'Maltese'),
  Language('lb', 'Luxemburguês', 'Luxembourgish'),
  Language('fy', 'Frísio', 'Western Frisian'),
  Language('af', 'Africâner', 'Afrikaans'),
  Language('sw', 'Suaíli', 'Swahili'),
  Language('zu', 'Zulu', 'Zulu'),
  Language('xh', 'Xhosa', 'Xhosa'),
  Language('yo', 'Iorubá', 'Yoruba'),
  Language('ig', 'Igbo', 'Igbo'),
  Language('ha', 'Hauçá', 'Hausa'),
  Language('am', 'Amárico', 'Amharic'),
  Language('so', 'Somali', 'Somali'),
  Language('mg', 'Malgaxe', 'Malagasy'),
  Language('ny', 'Chichewa', 'Chichewa'),
  Language('sn', 'Shona', 'Shona'),
  Language('st', 'Sesoto', 'Southern Sotho'),
  Language('rw', 'Kinyarwanda', 'Kinyarwanda'),
  Language('ta', 'Tâmil', 'Tamil'),
  Language('te', 'Télugo', 'Telugu'),
  Language('kn', 'Canarês', 'Kannada'),
  Language('ml', 'Malaiala', 'Malayalam'),
  Language('mr', 'Marati', 'Marathi'),
  Language('gu', 'Guzerate', 'Gujarati'),
  Language('pa', 'Panjabi', 'Punjabi'),
  Language('ne', 'Nepalês', 'Nepali'),
  Language('si', 'Cingalês', 'Sinhala'),
  Language('or', 'Oriá', 'Odia'),
  Language('as', 'Assamês', 'Assamese'),
  Language('sd', 'Sindi', 'Sindhi'),
  Language('ps', 'Pashto', 'Pashto'),
  Language('ku', 'Curdo', 'Kurdish'),
  Language('my', 'Birmanês', 'Burmese'),
  Language('km', 'Khmer', 'Khmer'),
  Language('lo', 'Laosiano', 'Lao'),
  Language('jv', 'Javanês', 'Javanese'),
  Language('su', 'Sundanês', 'Sundanese'),
  Language('ceb', 'Cebuano', 'Cebuano'),
  Language('haw', 'Havaiano', 'Hawaiian'),
  Language('mi', 'Maori', 'Maori'),
  Language('sm', 'Samoano', 'Samoan'),
  Language('ht', 'Crioulo haitiano', 'Haitian Creole'),
  Language('la', 'Latim', 'Latin'),
  Language('eo', 'Esperanto', 'Esperanto'),
  Language('yi', 'Iídiche', 'Yiddish'),
  Language('hmn', 'Hmong', 'Hmong'),
  Language('co', 'Corso', 'Corsican'),
  Language('ug', 'Uigur', 'Uyghur'),
  Language('tt', 'Tártaro', 'Tatar'),
  Language('tk', 'Turcomeno', 'Turkmen'),
];

/// Name of [code] in the app language [appLanguage]; an unknown code shows
/// as itself.
String languageName(String code, String appLanguage) {
  for (final l in languages) {
    if (l.code == code) return l.nameIn(appLanguage);
  }
  return code;
}

/// Caption language for someone who installs the app (D-29 A): the phone's
/// language when it is in the list, else English. [deviceTag] is the phone's
/// first language as a BCP 47 tag ("pt-BR", "zh-Hant-TW", "en_AU"). The full
/// code is tried first (with script, then with region), then the language
/// alone.
String defaultCaptionLanguage(String deviceTag) {
  final parts = deviceTag.split(RegExp('[-_]')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return 'en';
  var lang = parts.first.toLowerCase();
  // Old or alternative codes Android may report for a language on the list.
  lang = const {'iw': 'he', 'in': 'id', 'ji': 'yi', 'nb': 'no', 'nn': 'no', 'tl': 'fil'}[lang] ?? lang;
  String? script;
  String? region;
  for (final p in parts.skip(1)) {
    if (p.length == 4 && script == null) {
      script = p[0].toUpperCase() + p.substring(1).toLowerCase();
    } else if ((p.length == 2 || p.length == 3) && region == null) {
      region = p.toUpperCase();
    }
  }
  // Chinese without a script: Taiwan, Hong Kong and Macau write Traditional.
  if (lang == 'zh' && script == null) {
    script = const {'TW', 'HK', 'MO'}.contains(region) ? 'Hant' : 'Hans';
  }
  final codes = {for (final l in languages) l.code.toLowerCase(): l.code};
  for (final c in [if (script != null) '$lang-$script', if (region != null) '$lang-$region', lang]) {
    final hit = codes[c.toLowerCase()];
    if (hit != null) return hit;
  }
  return 'en';
}
