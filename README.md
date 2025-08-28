## usersテーブル

|Column             |Type   |Options                  |
|-------------------|-------|-------------------------|
|first_name         |string |null: false              |
|last_name          |string |null: false              |
|nickname           |string |null: false              |
|email              |string |null: false, unique: true|
|encrypted_password |string |null: false              |

### Association
has_many :travel_plans, dependent: :destroy


## travel_plansテーブル

| Column      | Type       | Options                         |
| ----------- | ---------- | ------------------------------- |
| user_id     | references | null: false, foreign_key: true  |
| name        | string     | null: false                     |
| start_date  | date       | null: false                     |
| end_date    | date       | null: false                     |
| budget      | integer    |                                 |
| notes       | text       |                                 |
| status      | string     | default: draft                  |

### Association
belongs_to :user
has_many :plan_days, dependent: :destroy
has_many :plan_destinations, dependent: :destroy
has_many :destinations, through: :plan_destinations


## destinations（マスタ）
| Column         | Type    | Options                   |
| -------------- | ------- | ------------------------- |
| prefecture_id  | integer | null: false, unique: true |
| name           | string  | null: false, unique: true |

### Association
has_many :plan_destinations
has_many :travel_plans, through: :plan_destinations


## plan_destinations（旅行プランと都道府県の中間DB）
| Column           | Type       | Options                         |
| ---------------- | ---------- | ------------------------------- |
| travel_plan_id   | references | null: false, foreign_key: true  |
| destination_id   | references | null: false, foreign_key: true  |

### Association
belongs_to :travel_plan
belongs_to :destination


## plan_days
| Column           | Type       | Options                         |
| ---------------- | ---------- | ------------------------------- |
| travel_plan_id   | references | null: false, foreign_key: true  |
| date             | date       | null: false                     |
| day_number       | integer    | null: false                     |

### Association
belongs_to :travel_plan
has_many :plan_items, dependent: :destroy


## categories（プラン項目マスタ）
| Column         | Type   | Options                   |
| -------------- | ------ | ------------------------- |
| category_code  | string | null: false, unique: true |
| name           | string | null: false, unique: true |

### Association
has_many :plan_items


## plan_items
| Column           | Type       | Options                         |
| ---------------- | ---------- | ------------------------------- |
| plan_day_id      | references | null: false, foreign_key: true  |
| category_id      | references | null: false, foreign_key: true  |
| title            | string     | null: false                     |
| description      | text       |                                 |
| image_url        | string     |                                 |
| reservation_url  | string     |                                 |

### Association
belongs_to :plan_day
belongs_to :category
belongs_to :travel_plan



## メモ
users：ユーザー管理

travel_plans：旅行プラン（全体の概要）

plan_days：プラン内の日別スケジュール

plan_items：日別スケジュールの中の宿泊・食事・観光などの詳細

destinations：行き先（都道府県）

plan_destinations：旅行プランと行き先の中間テーブル（複数都道府県対応）

recommendations：AIが提案する関連スポットやイベント