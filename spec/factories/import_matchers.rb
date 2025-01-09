FactoryBot.define do
  factory :import_matcher do
    account factory: :lloyds_account

    factory :import_matcher_octopus_energy do
      trx_type             { 'DD' }
      description          { 'OCTOPUS ENERGY'}
      description_is_regex { false }
    end

    factory :import_matcher_amazon do
      trx_type             { 'DEB' }
      description          { 'Amazon\.co\.uk\*[A-Z0-9]+'}
      description_is_regex { true }
    end
  end
end
