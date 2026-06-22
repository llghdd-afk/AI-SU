# frozen_string_literal: true

require 'sketchup.rb'

module LLGHD
  module LocalAIRender
    module Settings
      NAMESPACE = 'LLGHD_LocalAIRender'

      BUILTIN_CHANNEL = {
        '_type' => 'newapi_channel_conn',
        'endpoint' => 'https://www.fucheers.top/v1/images/edits',
        'api_key' => '',
        'model' => 'gpt-image-2',
        'request_mode' => 'openai_image_edit_multipart'
      }.freeze

      DEFAULTS = {
        'endpoint' => BUILTIN_CHANNEL['endpoint'],
        'api_key' => BUILTIN_CHANNEL['api_key'],
        'model' => BUILTIN_CHANNEL['model'],
        'request_mode' => BUILTIN_CHANNEL['request_mode'],
        'text_endpoint' => '',
        'text_api_key' => '',
        'planner_model' => 'gpt-5.5',
        'reference_model' => 'gpt-5.5',
        'backup_text_models' => '',
        'backup_text_endpoints' => '',
        'backup_text_api_keys' => '',
        'github_repo' => 'llghdd-afk/AI-SU',
        'github_asset' => 'LocalAIRender.zip',
        'github_direct_url' => 'https://github.com/llghdd-afk/AI-SU/archive/refs/heads/codex/pinterest-inspiration-skill.zip',
        'output_dir' => nil,
        'capture_width' => 1280,
        'capture_height' => 900
      }.freeze

      module_function

      def read(key, fallback = nil)
        default = fallback.nil? ? DEFAULTS[key] : fallback
        value = Sketchup.read_default(NAMESPACE, key, default)
        if key == 'output_dir' && (value.nil? || value.to_s.empty?)
          File.join(Sketchup.temp_dir, 'llghd_local_ai_render')
        else
          value
        end
      end

      def write(key, value)
        value = value.to_s.strip if value.is_a?(String)
        Sketchup.write_default(NAMESPACE, key, value)
      end

      def to_h
        DEFAULTS.keys.each_with_object({}) do |key, hash|
          hash[key] = read(key)
        end
      end

      def builtin_channel
        BUILTIN_CHANNEL.dup
      end
    end
  end
end
