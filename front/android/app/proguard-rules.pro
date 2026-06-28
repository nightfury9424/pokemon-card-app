# MLKit 텍스트 인식: 한국어(text-recognition-korean)만 사용.
# google_mlkit_text_recognition 플러그인이 미포함 다국어 인식기(중국어/일본어/데바나가리)를
# 참조 → R8 release 빌드에서 누락 클래스 경고. 미사용이므로 경고만 억제(-dontwarn).
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
