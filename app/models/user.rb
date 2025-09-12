class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  validates :first_name, presence: true
  validates :last_name, presence: true
  validates :nickname, presence: true
  validates :home_destination, presence: true
  belongs_to :home_destination, class_name: 'Destination', optional: false
  # 必須にしたい場合は optional: false にし、下記のバリデーションも有効

  has_many :travel_plans, dependent: :destroy
end
