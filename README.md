# Comment Player for iPad

Плеер для ревью видео на iPad: покадровая навигация, тайм-код из файла, комментарии
и пометки на кадре, выгрузка таблицы (XLSX / PDF) и маркеров для DaVinci Resolve и Premiere Pro.

План разработки — [ROADMAP.md](ROADMAP.md).

## Сборка (Mac)

Нужно: Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate          # создаёт CommentPlayer.xcodeproj из project.yml
open CommentPlayer.xcodeproj
```

В Xcode: выбрать свою команду в **Signing & Capabilities**, подключить iPad, нажать Run.

Тесты логики тайм-кода (без iPad):

```bash
cd Packages/FrameTimecode && swift test
```

## Структура

```
App/                          приложение (SwiftUI)
  Core/Timecode/              чтение тайм-кода из видеофайла (трек tmcd)
  Features/Player/            плеер и покадровая навигация
Packages/FrameTimecode/       тайм-код, частоты кадров, drop-frame + тесты
project.yml                   описание проекта для XcodeGen
```

## Горячие клавиши (Magic Keyboard)

| Клавиша | Действие |
|---|---|
| Пробел | Play / Pause |
| ← / → | −1 / +1 кадр |
| Shift + ← / → | −10 / +10 кадров |
