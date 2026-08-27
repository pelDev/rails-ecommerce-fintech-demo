require 'rails_helper'

RSpec.describe Merchant, type: :model do
  # Test data setup
  let(:valid_attributes) do
    {
      name: 'Test Merchant',
      status: :active
    }
  end

  describe 'validations' do
    context 'presence validations' do
      it 'is valid with valid attributes' do
        merchant = Merchant.new(valid_attributes)
        expect(merchant).to be_valid
      end

      it 'is invalid without a name' do
        merchant = Merchant.new(valid_attributes.except(:name))
        expect(merchant).to_not be_valid
        expect(merchant.errors[:name]).to include("can't be blank")
      end

      it 'is invalid without a status' do
        merchant = Merchant.new(valid_attributes.merge(status: nil))
        expect(merchant).to_not be_valid
        expect(merchant.errors[:status]).to include("can't be blank")
      end
    end

    context 'uniqueness validations' do
      before do
        Merchant.create!(valid_attributes)
      end

      it 'is invalid with a duplicate name' do
        duplicate_merchant = Merchant.new(valid_attributes)
        expect(duplicate_merchant).to_not be_valid
        expect(duplicate_merchant.errors[:name]).to include('has already been taken')
      end
    end

    context 'inclusion validations' do
      it 'is invalid with an invalid status' do
        expect {
          Merchant.new(name: 'Test', status: :invalid_status)
        }.to raise_error(ArgumentError, /'invalid_status' is not a valid status/)
      end

      it 'is valid with each valid status' do
        Merchant.statuses.each do |status_key, _value|
          merchant = Merchant.new(name: "#{status_key} Merchant", status: status_key)
          expect(merchant).to be_valid
        end
      end
    end
  end

  describe 'database constraints' do
    context 'null constraints' do
      it 'raises error when name is null' do
        expect {
          merchant = Merchant.new
          merchant.name = nil
          merchant.status = :active
          merchant.save!(validate: false)
        }.to raise_error(ActiveRecord::NotNullViolation)
      end

      it 'raises error when status is null' do
        expect {
          merchant = Merchant.new
          merchant.name = 'Null Status Merchant'
          merchant.status = nil
          merchant.save!(validate: false)
        }.to raise_error(ActiveRecord::NotNullViolation)
      end
    end

    context 'unique constraints' do
      before do
        Merchant.create!(name: 'Unique Merchant', status: :active)
      end

      it 'raises error with duplicate name at DB level' do
        expect {
          merchant = Merchant.new
          merchant.name = 'Unique Merchant'
          merchant.status = :inactive
          merchant.save!(validate: false)
        }.to raise_error(ActiveRecord::RecordNotUnique)
      end
    end

    context 'check constraints' do
      it 'raises error with invalid status value' do
        # Skip Rails validation and insert directly
        expect {
          Merchant.connection.execute(
            "INSERT INTO merchants (name, status, created_at, updated_at) VALUES ('Invalid Status Merchant', 99, NOW(), NOW())"
          )
        }.to raise_error(ActiveRecord::StatementInvalid, /check constraint/)
      end
    end
  end

  describe 'enums' do
    it 'defines correct enum values' do
      expect(Merchant.statuses).to eq({
        'active' => 0,
        'inactive' => 1,
        'suspended' => 2
      })
    end

    it 'provides enum query methods' do
      merchant = Merchant.create!(valid_attributes)
      expect(merchant.active?).to be true
      expect(merchant.inactive?).to be false
      expect(merchant.suspended?).to be false
    end

    it 'provides enum scope methods' do
      active_merchant = Merchant.create!(name: 'Active Merchant', status: :active)
      inactive_merchant = Merchant.create!(name: 'Inactive Merchant', status: :inactive)

      expect(Merchant.active).to include(active_merchant)
      expect(Merchant.active).to_not include(inactive_merchant)
    end
  end

  describe 'scopes' do
    before do
      @active_merchant = Merchant.create!(name: 'Active Merchant', status: :active)
      @inactive_merchant = Merchant.create!(name: 'Inactive Merchant', status: :inactive)
      @suspended_merchant = Merchant.create!(name: 'Suspended Merchant', status: :suspended)
    end

    it 'returns active merchants' do
      expect(Merchant.active).to include(@active_merchant)
      expect(Merchant.active).to_not include(@inactive_merchant)
      expect(Merchant.active).to_not include(@suspended_merchant)
    end

    it 'returns active or inactive merchants' do
      expect(Merchant.active_or_inactive).to include(@active_merchant)
      expect(Merchant.active_or_inactive).to include(@inactive_merchant)
      expect(Merchant.active_or_inactive).to_not include(@suspended_merchant)
    end
  end

  describe 'callbacks' do
    it 'normalizes the name before validation' do
      merchant = Merchant.create!(name: '  test merchant  ', status: :active)
      expect(merchant.name).to eq('Test Merchant')
    end

    it 'does not normalize nil or empty names' do
      merchant = Merchant.new(name: nil, status: :active)
      expect(merchant).to_not be_valid
      expect(merchant.errors[:name]).to include("can't be blank")
    end
  end

  describe 'instance methods' do
    let(:merchant) { Merchant.new(valid_attributes) }

    it 'returns correct boolean for active' do
      expect(merchant.active?).to be true
      merchant.status = :inactive
      expect(merchant.active?).to be false
    end

    it 'returns correct boolean for inactive' do
      merchant.status = :inactive
      expect(merchant.inactive?).to be true
    end

    it 'returns correct boolean for suspended' do
      merchant.status = :suspended
      expect(merchant.suspended?).to be true
    end
  end


  describe 'edge cases' do
    context 'with very long names' do
      it 'handles long names' do
        long_name = 'A' * 255
        merchant = Merchant.create!(name: long_name, status: :active)
        expect(merchant.name).to eq(long_name.strip.titleize)
      end
    end

    context 'with special characters in name' do
      it 'handles special characters' do
        merchant = Merchant.create!(name: 'Merchant & Co., Inc.', status: :active)
        expect(merchant.name).to eq('Merchant & Co., Inc.')
      end
    end

    context 'with edge case in status transitions' do
      it 'allows status changes' do
        merchant = Merchant.create!(valid_attributes)
        merchant.update!(status: :inactive)
        expect(merchant.reload.inactive?).to be true
      end
    end
  end
end
