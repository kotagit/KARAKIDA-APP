# 唐木田APP アーキテクチャ

## 図1：画面遷移フロー

```mermaid
flowchart TD
    A([起動]) --> B{AuthGate}
    B -->|未ログイン| C[LoginScreen]
    B -->|ログイン済| D[HomeScreen]
    C -->|Googleサインイン| D

    D --> E[発表\nAnnouncementScreen]
    D --> F[宣教\nSenkyoMenuScreen]
    D --> G[申請\nApplicationMenuScreen]
    D --> H[支援\nSupportScreen]
    D --> I[設定\nColorSettingsScreen]
    D -->|isAdmin| J[管理画面\nAdminScreen]

    F --> F1[マイ区域カード\nFileListScreen]
    F --> F2[オートロック区域\nNightTerritoryCardsScreen\ntype=AUTOLOCK]
    F --> F3[夜間区域\nNightTerritoryCardsScreen\ntype=NIGHT]
    F --> F4[公共エリア伝道\nPublicWitnessingTableScreen]

    F1 --> S[SheetViewScreen\n通常区域]
    F2 --> F2a[マンション一覧]
    F3 --> S2[SheetViewScreen\n夜間区域]

    G --> G1[公共エリア申請\nApplicationScreen]
    G --> G2[奉仕報告\nServiceReportScreen]
    G --> G3[公共エリア申込結果\nApplicationResultScreen]
    G --> G4[奉仕報告提出結果\nServiceReportResultScreen]
    G --> G5[区域情報登録\nAreaInfoRegistrationScreen]

    J -->|isCho| J1[区域カード配布\nAdminOverallAssignmentScreen]
    J -->|isPW| J2[公共エリア管理\nAdminPublicWitnessingScreen]
    J -->|isTerritoryServant| J3[グループ区域割当て\nAdminGroupTerritoryAssignmentScreen\ntype=NORMAL]
    J -->|isTerritoryServant| J4[夜間区域割当て\nAdminGroupTerritoryAssignmentScreen\ntype=NIGHT]
    J -->|isTerritoryServant| J5[AL区域割当て\nAdminGroupTerritoryAssignmentScreen\ntype=AUTOLOCK]
```

## 図2：Firestore コレクション × 利用画面（表）

| Firestoreコレクション | 初期化 | マイ区域 | 通常区域 | 夜間区域 | AL区域 | 公共申請 | 区域割当て | カード配布 | 区域情報登録 | 設定 |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| USER_LIST | ✓ | | | | | | | | | |
| USER_SETTINGS | ✓ | | | | | | | | | ✓ |
| CONFIG | ✓ | | | | | | | | | |
| GROUP_LIST | ✓ | | | | | | ✓ | ✓ | | |
| GROUP_ASS_NO | | ✓ | | | ✓ | | ✓ | | | |
| CARD_ASSIGNMENTS | | ✓ | | | | | | ✓ | | |
| AREA_LIST | | | | | | | ✓ | | | |
| AREA_DATA_NORMAL | | | ✓ | | | | | | | |
| AREA_DATA_NORMAL_HISTORY | | | ✓ | | | | | | | |
| AREA_DATA_NIGHT | | | | ✓ | | | | | | |
| AREA_DATA_NIGHT_HISTORY | | | | ✓ | | | | | | |
| AUTOLOCK_LIST | | | | | ✓ | | ✓ | | | |
| PUBLIC_WITNESSING_OPTIONS | | | | | | ✓ | | | | |
| PUBLIC_WITNESSING | | | | | | ✓ | | | | |
| VISIT_STATUS_OPTIONS | | | ✓ | | | | | | | |
| AREA_INFO_REQUESTS | | | | | | | | | ✓ | |
| ADMIN_NOTIFICATIONS | | | | | | | | | ✓ | |

## 図2：Firestore コレクション × 利用画面（グラフ）

```mermaid
graph LR
    subgraph Firestore["☁️ Firestore コレクション"]
        FS1[USER_LIST]
        FS2[USER_SETTINGS]
        FS3[CONFIG]
        FS4[GROUP_LIST]
        FS5[GROUP_ASS_NO]
        FS6[CARD_ASSIGNMENTS]
        FS7[AREA_LIST]
        FS8[AREA_DATA_NORMAL]
        FS9[AREA_DATA_NORMAL_HISTORY]
        FS10[AREA_DATA_NIGHT]
        FS11[AREA_DATA_NIGHT_HISTORY]
        FS12[AUTOLOCK_LIST]
        FS13[PUBLIC_WITNESSING_OPTIONS]
        FS14[PUBLIC_WITNESSING]
        FS15[PUBLIC_WITNESSING_ASSIGNMENTS]
        FS16[PREACHING_REPORT]
        FS17[VISIT_STATUS_OPTIONS]
        FS18[AREA_INFO_REQUESTS]
        FS19[ADMIN_NOTIFICATIONS]
    end

    subgraph App["📱 アプリ"]
        A1[AuthGate / SheetsProvider\n初期化]
        A2[HomeScreen\nマイ区域カード]
        A3[SheetViewScreen\n通常]
        A4[SheetViewScreen\n夜間]
        A5[NightTerritoryCardsScreen\nAUTOLOCK]
        A6[NightTerritoryCardsScreen\nNIGHT]
        A7[ApplicationScreen\n公共エリア申請]
        A8[AdminGroupTerritoryAssignment\n区域割当て]
        A9[AdminOverallAssignment\n区域カード配布]
        A10[AreaInfoRegistration\n区域情報登録]
        A11[ColorSettingsScreen\n設定]
    end

    FS1 --> A1
    FS2 --> A1
    FS3 --> A1
    FS4 --> A1

    FS6 --> A2
    FS5 --> A2
    FS8 --> A3
    FS9 --> A3
    FS17 --> A3
    FS10 --> A4
    FS11 --> A4
    FS5 --> A5
    FS12 --> A5
    FS5 --> A6
    FS10 --> A6

    FS13 --> A7
    FS14 --> A7

    FS7 --> A8
    FS5 --> A8
    FS4 --> A8
    FS12 --> A8

    FS6 --> A9
    FS4 --> A9

    FS18 --> A10
    FS19 --> A10

    FS2 --> A11
```

## 図3：Provider / Service 構造

```mermaid
flowchart TD
    subgraph Providers["🔄 Providers（状態管理）"]
        P1[AuthService\n- currentUser\n- isSignedIn\n- isAdmin\n- isCho etc.]
        P2[SheetsProvider\n- currentUserName\n- currentUserGroupName\n- selectedCard\n- cardAddresses]
        P3[ThemeProvider\n- primaryColor\n- accentColor]
    end

    subgraph Services["⚙️ Services"]
        S1[FirestoreService\n全Firestore操作]
        S2[AuthService\nGoogle認証]
        S3[DriveService\nGoogle Drive]
        S4[SheetsService\nGoogle Sheets]
    end

    subgraph DB["☁️ Firebase"]
        DB1[(Firestore)]
        DB2[Google Auth]
        DB3[Google Drive]
    end

    P1 --> S2 --> DB2
    P2 --> S1 --> DB1
    P3 --> S1
    S3 --> DB3
    S4 --> DB3
```
