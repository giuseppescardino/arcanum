# Arcanum — icone (A-serratura)

pubspec.yaml:

```yaml
flutter_launcher_icons:
  image_path: "assets/icon/icon_ios_light_1024.png"
  ios: true
  remove_alpha_ios: true
  android: true
  adaptive_icon_background: "assets/icon/android_background_432.png"
  adaptive_icon_foreground: "assets/icon/android_foreground_432.png"
  adaptive_icon_monochrome: "assets/icon/android_monochrome_432.png"
flutter_native_splash:
  color: "#283593"
  image: "assets/icon/splash_logo_512.png"
  color_dark: "#161826"
```

Le varianti iOS scura/tinta vanno aggiunte a mano in Assets.xcassets/AppIcon (Appearances: Dark, Tinted).
Colori: gradiente #5C6BC0 → #283593, chiaro #FAFBFF, ombra #E8EAF6, inchiostro #303F9F.
