#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

repo_dir = File.expand_path(ARGV.fetch(0, File.expand_path("..", __dir__)))
skills_dir = File.join(repo_dir, "skills")
max_description = 420
max_total_description = 6_000
errors = []
total_description = 0

def read_yaml_mapping(path, label, errors)
  data = YAML.safe_load(File.read(path, encoding: "UTF-8"))
  unless data.is_a?(Hash)
    errors << "#{label}: YAML must be a mapping"
    return nil
  end
  data
rescue Psych::SyntaxError => e
  errors << "#{label}: invalid YAML: #{e.message.lines.first.strip}"
  nil
end

skill_dirs = if Dir.exist?(skills_dir)
  Dir.glob(File.join(skills_dir, "*")).select { |path| File.directory?(path) }.sort
else
  []
end

errors << "#{skills_dir}: no skill directories found" if skill_dirs.empty?

skill_dirs.each do |skill_dir|
  skill_name = File.basename(skill_dir)
  skill_path = File.join(skill_dir, "SKILL.md")
  agents_path = File.join(skill_dir, "agents", "openai.yaml")

  unless File.file?(skill_path)
    errors << "#{skill_name}: missing SKILL.md"
    next
  end

  text = File.read(skill_path, encoding: "UTF-8")
  frontmatter = text.split(/^---\s*$/, 3)[1]
  if frontmatter.nil?
    errors << "#{skill_name}: missing YAML frontmatter"
  else
    begin
      data = YAML.safe_load(frontmatter)
      unless data.is_a?(Hash)
        errors << "#{skill_name}/SKILL.md: frontmatter must be a mapping"
        data = nil
      end
    rescue Psych::SyntaxError => e
      errors << "#{skill_name}/SKILL.md: invalid frontmatter: #{e.message.lines.first.strip}"
      data = nil
    end

    if data
      name = data["name"]
      description = data["description"]
      errors << "#{skill_name}: missing frontmatter name" unless name.is_a?(String) && !name.empty?
      errors << "#{skill_name}: skill name must match folder" unless name == skill_name
      if description.is_a?(String) && !description.empty?
        total_description += description.length
        if description.length > max_description
          errors << "#{skill_name}: description is #{description.length} characters; max is #{max_description}"
        end
      else
        errors << "#{skill_name}: missing frontmatter description"
      end
    end
  end

  unless File.file?(agents_path)
    errors << "#{skill_name}: missing agents/openai.yaml"
    next
  end

  agents = read_yaml_mapping(agents_path, "#{skill_name}/agents/openai.yaml", errors)
  next unless agents

  interface = agents["interface"]
  unless interface.is_a?(Hash)
    errors << "#{skill_name}/agents/openai.yaml: missing interface mapping"
    next
  end

  display_name = interface["display_name"]
  short_description = interface["short_description"]
  default_prompt = interface["default_prompt"]

  errors << "#{skill_name}: missing interface.display_name" unless display_name.is_a?(String) && !display_name.empty?
  if display_name.is_a?(String) && display_name.length > 40
    errors << "#{skill_name}: interface.display_name is longer than 40 characters"
  end
  unless short_description.is_a?(String) && !short_description.empty?
    errors << "#{skill_name}: missing interface.short_description"
  end
  if short_description.is_a?(String) && short_description.length > 80
    errors << "#{skill_name}: interface.short_description is longer than 80 characters"
  end
  unless default_prompt.is_a?(String) && !default_prompt.empty?
    errors << "#{skill_name}: missing interface.default_prompt"
  end
  if default_prompt.is_a?(String) && !default_prompt.include?("$#{skill_name}")
    errors << "#{skill_name}: interface.default_prompt should mention $#{skill_name}"
  end
end

if total_description > max_total_description
  errors << "skill descriptions total #{total_description} characters; max is #{max_total_description}"
end

errors.each { |error| warn error }
exit(errors.empty? ? 0 : 1)
