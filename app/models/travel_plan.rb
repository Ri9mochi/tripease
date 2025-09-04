class TravelPlan < ApplicationRecord
  # Association
  belongs_to :user
  has_many :plan_days, dependent: :destroy
  has_many :plan_destinations, dependent: :destroy
  has_many :destinations, through: :plan_destinations
  has_many :plan_items, through: :plan_days

  # Validations
  validates :name, presence: true, length: { maximum: 100 }
  validates :start_date, presence: true
  validates :end_date, presence: true
  validates :budget, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :status, presence: true, inclusion: { in: %w(draft published completed cancelled) }
  validate :end_date_after_start_date

  # Enum-like behavior for status (Rails 4.1+ feature)
  # これにより、`travel_plan.draft?` や `travel_plan.published!` のように
  # ステータスを扱いやすくなります。
  # データベースには文字列として保存されます。
  enum status: { draft: 'draft', published: 'published', completed: 'completed', cancelled: 'cancelled' }

  private

  # カスタムバリデーション: 終了日が開始日より後であることを確認
  def end_date_after_start_date
    return if end_date.blank? || start_date.blank?

    if end_date < start_date
      errors.add(:end_date, "は開始日より後の日付に設定してください。")
    end
  end
end
