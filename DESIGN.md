# Higgs Data Design System

이 문서는 `junyeo217.github.io`의 기존 포트폴리오와 그 안의 `/higgs-data/` 학습 페이지가 공유할 시각 원칙을 정리한다. 현재 구현 범위는 `/higgs-data/`이며 기존 홈 화면의 파일과 동작은 변경하지 않는다.

## 0. Research Log

- Concrete reference: `https://junyeo217.github.io/`의 Works 화면을 1280×900, 768×900, 375×812에서 실제 브라우저로 확인하고 `getComputedStyle`로 종이색, 먹색, 선, 고정 헤더, 비대칭 그리드, 탭 상태, 반응형 전환을 추출했다. 캡처는 `reference-works-{1280,768,375}.jpg`다.
- Explicit exclusions: 검은 오프닝/메인 화면, 타이핑 인트로, 87–120px 초대형 타이포그래피는 사용자 지시에 따라 가져오지 않는다.
- Content research: `Higgsfield_Project_Analysis_All_2026-08-14`의 292개 파일과 여섯 프로젝트를 전수 조사했다. 화면은 자료의 규모보다 학습 순서와 근거 상태를 우선한다.
- Deep-study revision (2026-08-21): 95개의 `prompts_part_*.md`에 네 개의 owner-level `prompts.md`가 더 있음을 재측정했다. v2는 99개 프롬프트 문서를 스트리밍 집계하고, 원문·통계·0건 발견·정정 이력을 같은 근거 체계로 연결한다.
- Interaction reference: beui.dev `tabs` 원본에서 밑줄형 선택 표시, 활성 패널의 4px 상승/불투명도 전환, 모든 패널의 DOM 유지, reduced-motion 경로를 메커니즘으로 채택했다. React/Motion 코드는 가져오지 않고 현재 정적 사이트에 맞는 CSS/vanilla JS로 구현한다.
- Skipped lanes: Lazyweb와 Imagen 시안은 구체적인 실사이트 레퍼런스가 이미 있어 불필요하다. 브랜드 자산·로고·카피는 복제하지 않는다.

## 1. Atmosphere & Identity

영화 제작 현장에서 오래 쓴 리서치 바인더처럼 보여야 한다. 밝은 무코팅 종이, 짙은 먹색, 얇은 구획선, 압축된 라벨, 넉넉한 여백으로 자료의 계층을 드러낸다. 시그니처는 화면 상단의 **수평 프로젝트 인덱스**다. 방문자는 한 줄의 탭을 따라 전체 원리에서 개별 제작 사례로 이동하고, 각 카드의 근거 표지로 ‘관찰된 사실’과 ‘팀 주장’과 ‘해석’을 즉시 구분한다.

## 2. Color

### Palette

| Role | Token | Value | Usage |
|---|---|---:|---|
| Surface / primary | `--hd-paper` | `#f0efeb` | 페이지 기본 종이 |
| Surface / secondary | `--hd-paper-2` | `#e8e6df` | 비교표, 인셋, 코드 블록 |
| Surface / inverse | `--hd-ink` | `#17150f` | 본문 먹색, 역상 영역 |
| Surface / soft-dark | `--hd-ink-2` | `#242119` | 역상 카드의 단계 |
| Text / primary | `--hd-text` | `#17150f` | 제목과 본문 |
| Text / secondary | `--hd-muted` | `rgba(23, 21, 15, .66)` | 설명과 메타데이터 |
| Text / tertiary | `--hd-faint` | `rgba(23, 21, 15, .72)` | 작은 번호와 보조 라벨도 WCAG AA 대비 유지 |
| Border / default | `--hd-line` | `rgba(23, 21, 15, .18)` | 주요 구획선 |
| Border / strong | `--hd-line-strong` | `rgba(23, 21, 15, .38)` | 선택 상태, 핵심 비교 |
| Accent / primary | `--hd-accent` | `#8a6a49` | 링크, 포커스, 핵심 표시 |
| Accent / hover | `--hd-accent-strong` | `#654b32` | 링크 활성 상태 |
| Evidence / observed | `--hd-observed` | `#315e4b` | 관찰된 아카이브 사실 |
| Evidence / reported | `--hd-reported` | `#745433` | 팀이 보고한 결과 |
| Evidence / synthesis | `--hd-synthesis` | `#3f5f78` | 교차 프로젝트 해석 |
| Evidence / limit | `--hd-limit` | `#813f38` | 검증 한계와 주의 |

### Rules

- 색은 근거 상태와 상호작용 상태에만 의미를 부여한다. 표지는 문구와 선 모양을 함께 써 색만으로 구분하지 않는다.
- 표면 깊이는 그림자가 아니라 종이 톤과 선 굵기로 만든다.
- CSS에서 색을 추가하려면 먼저 이 표에 의미와 대비 근거를 추가한다.

## 3. Typography

### Scale

| Level | Size | Weight | Line height | Tracking | Usage |
|---|---|---:|---:|---:|---|
| Page title | `clamp(2.25rem, 5vw, 4rem)` | 560 | 1.02 | `-.045em` | 페이지 제목, 한 번만 사용 |
| H1 / panel title | `clamp(2rem, 4vw, 3rem)` | 560 | 1.1 | `-.035em` | 각 탭의 제목 |
| H2 / section | `clamp(1.35rem, 2.4vw, 2rem)` | 560 | 1.25 | `-.025em` | 학습 섹션 |
| H3 / card | `1.0625rem` | 650 | 1.4 | `-.01em` | 카드 제목 |
| Lead | `clamp(1.05rem, 1.8vw, 1.35rem)` | 430 | 1.65 | `-.01em` | 패널 리드 |
| Body | `1rem` | 400 | 1.75 | `-.01em` | 기본 본문 |
| Body / small | `.875rem` | 400 | 1.65 | `0` | 메모와 표 설명 |
| Label | `.6875rem` | 650 | 1.35 | `.16em` | 탭, 근거 표지, 메타 |
| Micro | `.625rem` | 650 | 1.35 | `.14em` | 번호와 지표 단위 |

### Font Stack

- Primary: `-apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", "Noto Sans KR", "Segoe UI", "Malgun Gothic", sans-serif`
- Mono: `ui-monospace, "SFMono-Regular", Consolas, monospace`
- 외부 폰트 요청 없이 운영체제의 한국어 시스템 산세리프를 사용한다. 초기 렌더 지연을 피하고 초대형 타입이나 타이핑 효과를 만들지 않는다.

### Rules

- 한국어 본문은 `word-break: keep-all`; 긴 영문 식별자와 URL에는 국소적으로 `overflow-wrap: anywhere`를 쓴다.
- 본문은 14px 아래로 내리지 않는다. 라벨만 의미가 짧고 반복될 때 10–11px을 허용한다.
- 제목이 모바일에서 네 줄 이상이 되면 크기를 낮추고 의미 단위로 줄바꿈한다.

## 4. Spacing & Layout

### Base Unit

모든 의도형 간격은 4px 배수다.

| Token | Value | Usage |
|---|---:|---|
| `--hd-space-1` | `4px` | 표지 내부 미세 간격 |
| `--hd-space-2` | `8px` | 인라인 요소 |
| `--hd-space-3` | `12px` | 라벨과 제목 |
| `--hd-space-4` | `16px` | 카드 내부 기본 |
| `--hd-space-5` | `20px` | 모바일 페이지 패딩 |
| `--hd-space-6` | `24px` | 카드 그룹 |
| `--hd-space-8` | `32px` | 섹션 내부 |
| `--hd-space-10` | `40px` | 중간 구획 |
| `--hd-space-12` | `48px` | 패널 소구획 |
| `--hd-space-16` | `64px` | 큰 섹션 경계 |
| `--hd-space-20` | `80px` | 데스크톱 패널 상단 |
| `--hd-nav-width` | `240px` | 심화 탭 내부의 고정 목차 폭 |
| `--hd-code-max` | `46rem` | 원문 인용 본문의 편안한 읽기 폭 |

### Grid

- 최대 콘텐츠 폭: 1440px.
- 가로 패딩: `clamp(20px, 4vw, 64px)`.
- 데스크톱: 12열 개념, 본문은 주로 4/8 또는 5/7 비대칭 분할.
- 태블릿 768–1023px: 한 열을 기본으로 하되 지표는 2열 유지 가능.
- 모바일 0–767px: 20px 패딩, 모든 핵심 콘텐츠 1열, 수평 스크롤은 탭 레일만 허용.
- 탭 레일은 헤더 안에서 자체 스크롤을 갖고, 본문에는 수평 스크롤이 생기지 않는다.
- 심화 탭 내부는 데스크톱에서 `240px / minmax(0, 1fr)` 목차·본문 2열이다. 목차만 sticky이고 문서가 스크롤 소유자다.
- 1023px 이하에서는 목차가 본문 위 수평 섹션 레일로 바뀐다. 375px에서도 섹션 링크와 코드 블록만 자체 스크롤하며 페이지 자체는 넘치지 않는다.

## 5. Components

### Site Shell

- **Structure**: skip link → sticky header(wordmark + tablist) → main(tabpanels) → footer.
- **Variants**: desktop, tablet, mobile scroll rail.
- **States**: header remains readable over paper; no transparent overlap with content.
- **Accessibility**: one main landmark, one labelled navigation, skip link, 44px minimum targets.
- **Motion**: none.
- **Layout**: document scroll owner; header is sticky, not a fixed-height app shell.

### Project Tab Rail

- **Structure**: `role=tablist` containing eight `button[role=tab]`, one reusable underline indicator per active trigger.
- **Variants**: full rail, horizontally scrollable rail.
- **States**: default muted; hover/focus primary; active primary + 1px underline; disabled uses native disabled and does not participate in navigation.
- **Accessibility**: roving `tabindex`; ArrowLeft/Right, Home, End; `aria-controls`/`aria-labelledby`; hash deep-linking; selected tab scrolled into view.
- **Motion**: active panel opacity + 4px translate for 180ms; underline uses transform/opacity only. Reduced motion sets duration to zero and removes translation.
- **Layout**: cluster with inline scroll owner.

### Evidence Badge

- **Structure**: short Korean label plus optional definition; uppercase/compact label style.
- **Variants**: observed, reported, synthesis, limit.
- **States**: static; links inside use visible hover/focus.
- **Accessibility**: label text conveys the state without color; no icon-only state.
- **Motion**: none.

### Metric Strip

- **Structure**: definition list of value, unit, and definition.
- **Variants**: overview six-up desktop, project four-up desktop, stacked mobile.
- **States**: default only; metric definitions remain visible or reachable immediately below.
- **Accessibility**: numbers use tabular figures; labels are never title attributes only.
- **Motion**: none; no decorative count-up.

### Insight Card

- **Structure**: evidence badge → numbered label → heading → explanation → takeaway/source note.
- **Variants**: standard, inverse emphasis, caution.
- **States**: static; linked source rows receive underline/arrow affordance.
- **Accessibility**: semantic article/heading order, no card-wide ambiguous link.
- **Motion**: none.

### Reference Role Matrix

- **Structure**: semantic table on wide screens; same table remains scrollable with a visible scroll cue on narrow screens.
- **Variants**: overview and compact project view.
- **States**: row hover is informational only and therefore no animation is added.
- **Accessibility**: caption, column headers, row headers, readable at 200% zoom.
- **Motion**: none.

### Prompt Anatomy

- **Structure**: ordered sequence of named prompt blocks with concise purpose and failure symptom.
- **Variants**: 10-stage overview, project-specific compact form.
- **States**: static.
- **Accessibility**: real ordered list; mono styling only for tokens, never whole paragraphs.
- **Motion**: none.

### Project Section

- **Structure**: panel header → at-a-glance metrics → why-it-matters → workflow → four technique groups → archive limits.
- **Variants**: six project identities using the same anatomy.
- **States**: active tab panel visible; inactive panels remain in DOM with `hidden`.
- **Accessibility**: each panel owns one H1 and its sections descend in order.
- **Motion**: panel transition only.

### Section Navigator

- **Structure**: 현재 패널의 8–9개 `section[id]`로 연결되는 짧은 번호·이름 링크 목록. 데스크톱은 좌측 sticky, 태블릿·모바일은 본문 위 수평 레일이다.
- **Variants**: overview, project, compact author. 작성자 탭에는 심화 목차를 강제하지 않는다.
- **States**: 기본 muted, hover/focus primary, 현재 섹션은 `aria-current="location"`과 강한 왼쪽 선/밑줄로 함께 표시한다.
- **Accessibility**: 패널마다 고유한 `aria-label`; 해시 이동 뒤 제목이 sticky header 아래에 보이고 키보드 포커스를 빼앗지 않는다.
- **Motion**: 기본 smooth scroll은 기존 토큰을 사용하고 reduced motion에서는 즉시 이동한다. 장식 이동은 없다.

### Quantitative Chart

- **Structure**: `figure` → 제목·근거 표지 → CSS bar 또는 inline SVG → 수치가 적힌 legend/data list → `figcaption`의 계산식·출처·해석.
- **Variants**: horizontal bars, distribution buckets, cross-project comparison, folder-depth scale.
- **States**: 정적. hover만으로 값을 숨기지 않는다.
- **Accessibility**: 모든 값을 DOM 텍스트로 반복하고 SVG는 보조적 시각화다. 색뿐 아니라 레이블·패턴·순서로 구분한다.
- **Motion**: 없음. 차트가 뷰포트 진입 때 자라거나 카운트업하지 않는다.

### Prompt Evidence Block

- **Structure**: evidence badge → 익명 슬롯·문자 수·도구·해상도·SHA 칩 → `details/summary` → `pre > code` 원문 → “무엇을 하는가 / 왜 쓰는가 / 재사용 포인트” 해설 → 출처 상태.
- **Variants**: verified archive prompt, brief-embedded excerpt, unavailable-corpus limitation.
- **States**: closed/open, keyboard-native. 첫 번째 대표 원문은 열린 상태로 시작할 수 있다.
- **Accessibility**: summary는 원문의 역할을 설명하고, 긴 코드에는 국소 스크롤과 `aria-label`을 제공한다. 익명 슬롯 외 계정·owner 문자열은 공개하지 않는다.
- **Motion**: native disclosure only; no animated height.

### Named Technique Card

- **Structure**: 번호·근거 표지 → 고유 기법명 → 적용 조건 → 짧은 원문 예시 → 복사 가능한 실행 규칙 → 실패 신호.
- **Variants**: observed, reported, synthesis, limitation.
- **States**: static. 카드 전체 링크나 장식 hover가 없다.
- **Accessibility**: 원문은 인용 부호와 출처를 갖고, 제목만 읽어도 기법 간 차이를 알 수 있다.
- **Motion**: none.

### Deep Case

- **Structure**: 사례 제목 → 메타데이터 칩 → 검증된 media 또는 명시적 text-only fallback → prompt evidence → 구조 포인트 목록 → 결과를 과장하지 않는 한계.
- **Variants**: verified public media, poster fallback, media unavailable.
- **States**: video는 사용자 재생 제어를 제공하되 `muted loop playsinline preload="none" poster`를 기본으로 한다. 로드 실패 플레이어는 배포하지 않는다.
- **Accessibility**: media에는 설명 캡션·원본 페이지 링크, text-only에는 누락 이유가 있다. 자동 음성 재생은 금지한다.
- **Motion**: 사용자가 재생한 미디어 외 장식 모션 없음.

### Correction Record

- **Structure**: 초기값 → 재검증 값 → 측정 방법 → 정정 이유 → 날짜 → 영향받는 해석.
- **Variants**: corpus count, snapshot count, unavailable source.
- **States**: static.
- **Accessibility**: 화살표만으로 의미를 전달하지 않고 문장으로 변화 방향을 적는다.
- **Motion**: none.

### Author Contact Row

- **Structure**: visible channel name, account/address, external-link arrow as SVG or text glyph, descriptive link label.
- **Variants**: social, email, portfolio.
- **States**: default line; hover/focus shifts line/accent; active 1px translate only.
- **Accessibility**: explicit destination in accessible name; `mailto:` for email; no icon-only links.
- **Motion**: 140ms color/transform; reduced motion disables transform.

## 6. Motion & Interaction

| Token | Value | Usage |
|---|---|---|
| `--hd-motion-micro` | `140ms` | link/button press and color response |
| `--hd-motion-panel` | `180ms` | selected-panel entrance |
| `--hd-ease-out` | `cubic-bezier(.16, 1, .3, 1)` | reference-derived settle |

- Motion only explains selection or confirms an affordance. Static teaching cards never float, tilt, pulse, or reveal on scroll.
- Animate only `transform`, `opacity`, `filter`, and color where appropriate; never animate width/height/position.
- Interactions remain interruptible and keyboard-equivalent.
- `prefers-reduced-motion: reduce` removes transforms and sets transitions/scroll behavior to immediate.

## 7. Depth & Surface

Strategy: **borders + tonal shift**.

- Level 0: primary paper, no border.
- Level 1: section split with `1px solid var(--hd-line)`.
- Level 2: secondary paper inset with strong top rule.
- Level 3: inverse ink panel reserved for one synthesis/caution block per panel at most.
- No box shadows. No glass blur. No decorative gradients. No rounded card grid; only evidence pills may use a full radius.

## 8. Accessibility Constraints & Accepted Debt

### Constraints

- Target WCAG 2.2 AA with Lighthouse accessibility 100.
- Body contrast at least 4.5:1; large text and boundaries at least 3:1.
- Complete keyboard tab flow; selected-tab focus, direct hash, Back/Forward navigation, skip link, visible focus.
- 44×44px minimum tab and contact targets.
- At 375px, 768px, 1280px and 200% zoom: no primary-content horizontal overflow or clipped Korean glyphs.
- Screen reader: unique landmark names, valid heading hierarchy, correct tab/tabpanel relationships, table captions, explanatory link text.
- Cognitive: stable anatomy across six project panels; evidence vocabulary remains identical; metrics define their units; no auto-advancing content.
- Cognitive: 8–9개 섹션 목차는 모든 프로젝트에서 같은 순서를 유지한다. 긴 원문은 disclosure로 접되 역할·메타·해설은 접기 전에도 보인다.
- Data literacy: 차트마다 원수치, 계산식, 분모, 스냅샷 날짜, 등급, 해석 한 문장을 함께 둔다. 0건은 실제로 센 모집단이 명시될 때만 사용한다.
- Motion: reduced-motion path is feature-complete.
- Content: no raw contributor identifiers, unsafe imitation instructions, copyright-evasion wording, or unlabelled team claims.

### Inclusive Personas

- **제작 학습자 민지**: 처음 Higgsfield 사례를 공부하며 ‘공통 원리 → 프로젝트 예시 → 주의점’ 경로를 완주해야 한다.
- **모바일 감독 현우**: 375px 화면에서 한 손 스크롤과 탭 이동으로 어떤 프로젝트든 읽고, 가로 흔들림 없이 지표를 비교해야 한다.
- **키보드·스크린리더 사용자 서연**: 탭 목록을 방향키로 이동하고 선택 상태와 패널 제목을 정확히 들어야 한다.
- **모션 민감 사용자 도윤**: reduced-motion에서 내용·피드백 손실 없이 즉시 전환되어야 한다.
- **근거 검증자 준**: 차트·파생 지표·원문 인용을 출처 경로와 SHA까지 역추적하고, 초기값 정정과 자료 부재를 구분해야 한다.

### Accepted Debt

없음. 발견된 접근성·CJK·반응형 부채는 공개 전 수정한다.

## 9. Deep-study Content Contract

| Surface | Required anatomy | Release proof |
|---|---|---|
| Overview | 수집 범위, 교차 규모·도구·길이 차트, 공통/고유 기법 매트릭스, 상충 사례, 정정 이력, 검증 한계 | 태그 제거 8,000자 목표, 차트 3개 이상, 모든 수치의 계산식·등급 |
| Project tab ×6 | 개요, 수집 범위, 프롬프트 통계, 블록/키워드 차트, 파생 지표, 0건 또는 D 한계, 원문 6건, 이름 붙은 기법 4–6개, 사례 2–3개, 시사점·한계 | 원문 `pre/code`를 제외한 설명문 8,000자 이상 + 탭별 정량 감사 JSON + 원문 표본 SHA 검증 + 375/768/1280 캡처 |
| Author | 기존 연락처·방법론·읽기 가이드 유지 | 링크 4개와 탭 회귀 검증 |

- 8,000자는 반복을 허용하는 최소치가 아니라 A–F 증거층으로 채우는 목표다. 검증기는 긴 영문 원문이 설명의 깊이를 대신하지 않도록 `pre/code`를 제외한 정규화 설명문도 별도로 센다. 원문 아카이브가 없는 프로젝트는 허위 원문을 만들지 않고 D등급 대체 근거와 부족분을 수치로 밝힌다.
- 공개 HTML에는 `user_` 식별자, owner 폴더명, 계정 핸들, 개인 식별정보가 0건이어야 한다. 내부 추출 결과도 공개용과 private provenance를 분리한다.
- 모든 deep case는 실제로 로드되는 공식 미디어 또는 media-unavailable 설명 중 정확히 하나를 가진다. 빈 `video`/`img`/`iframe`은 실패다.
- 새 CSS/JS는 현재 v1 토큰과 vanilla stack 안에서만 확장한다. 외부 차트·폰트·모션 라이브러리와 CDN은 추가하지 않는다.
