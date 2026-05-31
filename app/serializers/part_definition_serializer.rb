class PartDefinitionSerializer
  include Alba::Resource

  transform_keys :lower_camel

  attributes :id, :part_number, :name, :description, :revision, :status

  attribute :created_at do |part|
    part.created_at.utc.iso8601(3)
  end

  attribute :updated_at do |part|
    part.updated_at.utc.iso8601(3)
  end
end
