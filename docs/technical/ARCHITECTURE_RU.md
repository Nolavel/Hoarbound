# Hoarbound — Техническая архитектура

> **АВТОРСКОЕ РЕШЕНИЕ / КАНОНИЧЕСКИЙ ТЕХНИЧЕСКИЙ КОНТРАКТ**
>
> Hoarbound **не переходит на полный ECS** как архитектуру всего проекта. ECS / data-oriented подход допускается только локально, в тех подсистемах, где масштаб, профилирование или характер симуляции дают от него конкретную пользу. Это сознательное решение автора, обусловленное жанром: Hoarbound — системный survival от третьего лица, где рядом с игроком существует небольшое число очень сложных физических и интерактивных объектов, а в мире потенциально может быть большое количество более простого состояния.
>
> Английская версия: [`ARCHITECTURE.md`](ARCHITECTURE.md). Оба файла должны оставаться смыслово синхронными. При расхождении формулировок последнее явное решение автора имеет приоритет.

Этот документ определяет техническое направление production-кодовой базы. Это не снимок каждой текущей реализации: фактическое состояние систем фиксирует `docs/GDD.md`. Здесь записано, **к какой форме должен двигаться код**.

## 1. Архитектурное направление

Целевая модель:

`Godot Scene / Component Shell -> Domain Core -> Authoritative State -> Presentation`

Плюс локальные data-oriented / ECS-острова только там, где они действительно оправданы.

Проект не должен переписываться вокруг заранее придуманного универсального framework. Существующие production-системы постепенно приводятся к этой модели по мере реальной работы над ними.

## 2. Почему Hoarbound не pure ECS

Главная инженерная проблема Hoarbound — не обновление десятков тысяч однородных gameplay entities. Основная сложность — понятный ownership небольшого числа сложных телесных систем:

- Генри, locomotion и animation;
- руки, переносимые предметы и физический inventory;
- contextual interaction и attention;
- camera;
- shelter, окна, печь и бытовые действия;
- survival state;
- weather и exposure мира;
- persistence и streaming.

Полный ECS сам по себе не устранит эти проблемы ownership. Он может лишь заменить Node-coupling на entity/component/system-coupling и добавить ещё один мост обратно к Godot scenes, animation, physics и presentation.

Поэтому ECS для Hoarbound — **инструмент**, а не фундамент всей игры.

## 3. Godot-native shell

Godot остаётся runtime-оболочкой для того, что он уже хорошо моделирует:

- scenes и authored world objects;
- physics bodies, collision и queries;
- animation и skeleton presentation;
- rendering и materials;
- camera nodes;
- audio emitters;
- physical props и interactable scene instances;
- editor-time composition и authoring.

Не следует бороться с движком и пересобирать эти механизмы внутри собственного framework без измеренной причины.

Node должен существовать потому, что участвует в scene/runtime lifecycle, а не просто как контейнер данных. Для состояния и правил, которым не нужен SceneTree ownership, предпочтительны обычные данные, `Resource`, `RefCounted` или небольшие domain-объекты.

## 4. Domain core

Gameplay-решения должны постепенно становиться независимыми от случайной структуры SceneTree.

Хорошие кандидаты для domain logic:

- правила выбора и разрешения interaction;
- ownership inventory;
- правила hands / carry transactions;
- thermal и wetness calculations;
- fuel и burn state;
- weather state и exposure evaluation;
- преобразование save / restore state;
- persistent world-object state;
- расчёты route / shelter condition.

Godot shell собирает физические и runtime-факты и исполняет результат. Domain layer решает, что эти факты **значат для gameplay**.

Цель не в функциональной чистоте ради чистоты. Цель — чтобы основные правила можно было понять без прохода по цепочкам scene lookups.

## 5. Один owner на authoritative state

На каждый важный вопрос должен существовать один ясный владелец.

| Вопрос / состояние | Предполагаемый owner |
|---|---|
| Что Генри держит? | Hands / carry ownership |
| Что принадлежит inventory? | Inventory |
| Thermal / survival state Генри | Survival / thermal domain |
| Текущая погода | Weather |
| Что сейчас означает `F` | Interaction intent |
| Финальный camera transform | Camera pipeline |
| Persistent state выгруженных объектов | World persistence |
| Отображение состояния | UI / animation / VFX, но не authoritative owner |

Нельзя допускать, чтобы UI, Player, inventory и world object хранили каждый свою версию одного факта.

Если двум системам нужна одна информация, одна система ею владеет, другая наблюдает или делает запрос.

## 6. Commands и contracts вместо reach-through

Связь между системами должна идти через узкие понятные контракты, а не через знание внутреннего scene tree соседней системы.

Предпочтительны отношения вроде:

`Interaction -> Hands.request_take(item)`

`Interaction -> Locomotion.request_approach(target)`

`World object -> Inventory.try_store(item)`

вместо цепочек:

`get_node(...) -> has_method(...) -> call(...)`

Signals подходят для факта «что-то произошло». Commands / явные методы подходят, когда один owner просит другой owner выполнить действие.

Не следует создавать глобальную event bus только для того, чтобы спрятать зависимости. Зависимости должны оставаться видимыми и направленными.

## 7. Cross-language capability contracts

Когда контракт подсистемы должен одинаково работать между разными типами Node и разными языками реализации, Hoarbound использует маленькую Godot-visible capability boundary.

Production-правило:

`public capability contract -> Godot Object / Variant boundary -> private GDScript, C# или C++ implementation`

Runtime-механизм живёт в `core/contracts/`. `CapabilityContract` хранит descriptor capability прямо на существующем owner `Object` через Godot metadata. Descriptor содержит устойчивый capability id, provider `Object` и map `logical operation -> Godot-visible method name`. Consumer работает через capability-specific adapter и не знает язык или конкретный класс provider.

Для этого **не создаётся отдельная Port-нода на каждый компонент**. Компонент не обязан иметь capability просто потому, что он существует. Capability вводится только когда другой subsystem действительно нуждается в стабильной границе, когда разные несвязанные классы должны выполнять один контракт или когда implementation language может быть заменён.

Dynamic reflection и string dispatch считаются механизмом границы, а не обычным gameplay-паттерном. Новые проверки `has_method()` / string-`call()` не должны расползаться по gameplay-коду; validation и invocation находятся внутри `core/contracts/` либо language adapter в этой зоне. Старые duck-typed protocols переносятся туда по мере работы с их owner-системами, без глобального rewrite.

`SaveParticipantCapability` — первая production-реализация правила. Старые providers с `get_save_key/get_save_data/load_save_data` адаптируются на границе, а explicit capability может сопоставить совсем другие имена методов. Поэтому consumer остаётся неизменным независимо от того, написан provider на GDScript, C# или C++.

### Рабочий пример: `SaveParticipantCapability`

Коллаборатору достаточно помнить три шага: один раз опубликовать capability owner-а, дальше обращаться только к публичному capability API, а детали реализации оставить приватными.

GDScript-owner может явно опубликовать свои существующие методы:

```gdscript
SaveParticipantCapability.publish(
	self,
	self,
	&"get_save_key",
	&"get_save_data",
	&"load_save_data"
)
```

Consumer не вызывает эти implementation-методы напрямую:

```gdscript
var key: StringName = SaveParticipantCapability.get_key(owner)
var data: Variant = SaveParticipantCapability.capture(owner)
SaveParticipantCapability.restore(owner, data as Dictionary)
```

C# или C++/GDExtension provider может иметь совсем другие приватные имена, например `stable_id`, `snapshot`, `restore_snapshot`, и сопоставить их тем же logical operations:

```text
save_participant
├── key     -> stable_id
├── capture -> snapshot
└── restore -> restore_snapshot
```

Consumer всё равно использует `SaveParticipantCapability.get_key/capture/restore`; при смене языка provider-а он не меняется.

```text
СЕЙЧАС                              ПОСЛЕ ДОКАЗАННОГО BOTTLENECK
SaveManager                         SaveManager
    │                                   │
SaveParticipantCapability           SaveParticipantCapability
    │                                   │
WeatherController.gd                WeatherController.cpp / GDExtension
```

Правило: **меняем implementation за capability, а не consumer-facing contract**. Новый capability создаётся только для реальной межсистемной границы; не нужно оборачивать capability каждый класс.

Для оптимизации GDExtension/C++ является заменяемой implementation за тем же контрактом. Последовательность:

`измеренный bottleneck -> сохранить capability id/operations -> заменить implementation -> повторить тот же consumer/runtime validation`

C++ не вводится просто потому, что он доступен, и перенос hot path в C++ не должен создавать вторую gameplay-архитектуру.

## 8. Simulation authoritative; presentation derived

Gameplay-state не должен зависеть от того, показывает ли его сейчас animation, UI, shader или particle effect.

Направление:

`authoritative state -> presentation`

а не:

`presentation -> gameplay truth`

Примеры:

- animation может показывать предмет в руке, но Hands решает, держит ли Генри его реально;
- frost shader показывает иней, но room/window state хранит величину эффекта;
- HUD показывает survival state, но не владеет им;
- VFX показывает ветер и снег, но не становится weather model.

## 9. Persistent Entity Identity

Выгрузка scene не должна определять, существует ли persistent world object.

Модель:

`persistent ID -> authoritative state -> loaded scene representation`

Scene может исчезнуть из дерева, но состояние остаётся для save/load и последующего восстановления.

Это особенно важно для:

- doors и windows;
- shelter repairs;
- loot и consumed items;
- fires и fuel;
- placed objects;
- world damage;
- streaming chunks;
- будущей долгоживущей world simulation.

Нельзя делать lifetime scene instance единственным местом, где хранится история объекта.

## 10. Направление Interaction

Interaction должен двигаться к pipeline с явными ответственностями:

`Sensors -> Candidates -> Attention Resolver -> Interaction Intent -> Executor -> subsystem owner`

Типичные owners: Hands, Locomotion, Inventory и сам world object.

Текущий interaction path не должен бесконечно разрастаться в один компонент, который одновременно владеет targeting, attention, storage, approach, animation, hands, UI semantics и всеми будущими режимами взаимодействия.

Разделять следует по ownership, когда ответственность становится самостоятельной, а не просто потому, что файл стал длинным.

## 11. Направление Camera

У камеры должен быть один финальный owner и один упорядоченный pipeline:

`Player intent -> Base camera target -> Context modifiers -> Collision / occlusion -> Presentation smoothing -> Final camera`

Shoulder state, passage framing, interaction framing, auto-look и похожие механики должны становиться modifiers / inputs этого pipeline, а не независимыми системами, каждая из которых немного двигает камеру.

Несколько подсистем не должны независимо владеть финальным camera transform.

## 12. Локальные ECS / data-oriented острова

ECS / data-oriented структуры допустимо рассматривать там, где задача действительно массовая и однородная, например:

- большие таблицы persistent world state;
- массовая wildlife / ambient simulation;
- streaming / LOD bookkeeping;
- spatial environmental sampling;
- большое количество footprint / decal metadata;
- batch processing простых environmental entities;
- будущие симуляции, где profiling показывает реальную стоимость Node/object overhead.

Они **не являются архитектурой по умолчанию** для:

- Генри;
- hands и embodied inventory;
- contextual interaction;
- camera;
- физического рюкзака;
- shelter rituals;
- уникальных физических props со сложным authored behaviour.

Перед введением ECS-подсистемы нужно назвать конкретную проблему масштаба / производительности / сложности, которую она решает, и описать её мост к production Godot path.

## 13. Никакого speculative framework

Не строить универсальный «Hoarbound framework» под гипотетические будущие системы.

Предпочтительная последовательность:

`конкретная production-проблема -> ясный owner -> маленький устойчивый contract -> второй реальный use case -> generalize при пользе`

Переиспользуемая abstraction обычно должна иметь минимум два реальных production-потребителя, а не оправдываться воображаемой будущей гибкостью.

Избегать:

- generic managers без конкретного state responsibility;
- compatibility layers, сохраняющих obsolete implementations;
- wrappers поверх engine-native механизмов без доказанной необходимости;
- parallel architecture paths для одной и той же gameplay responsibility.

Capability layer намеренно остаётся маленькой инфраструктурой и не является разрешением создавать interfaces для каждого класса.

## 14. Политика refactoring

Этот документ задаёт направление, но **не разрешает глобальный rewrite**.

При работе с существующей production-системой:

1. определить owner authoritative state;
2. найти cross-system reach-through и duplicated state;
3. сохранить player-facing behaviour, если задача его не меняет;
4. переносить по одной ответственности к явному contract;
5. если seam проходит между разными implementation languages, провести его через существующий capability либо добавить минимальный реально нужный capability;
6. удалять obsolete paths после доказанного replacement;
7. проверять реальный runtime path.

Не следует останавливать разработку игры ради теоретической архитектурной чистоты. Consolidation должен снижать риск и облегчать следующую работу.

## 15. Что здесь означает коммерчески здоровая архитектура

Цель — не модное название архитектуры. Система считается здоровой, если новый collaborator быстро отвечает:

- кто владеет state?
- кто имеет право его менять?
- как другая система просит изменение?
- что относится к simulation, а что к presentation?
- что сохраняется после unload scene?
- какой path production, а какой experimental?
- если implementation меняет язык, какой public contract остаётся неизменным?

Если ответы ясны, система движется к production shape.
