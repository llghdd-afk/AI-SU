# frozen_string_literal: true

require 'base64'
require 'json'
require 'net/http'
require 'openssl'
require 'timeout'
require 'uri'
require 'fileutils'

module LLGHD
  module LocalAIRender
    class ApiClient
      CONNECTION_ERRORS = [
        OpenSSL::SSL::SSLError,
        EOFError,
        Errno::ECONNRESET,
        Errno::ECONNREFUSED,
        Errno::ETIMEDOUT,
        Net::OpenTimeout,
        SocketError,
        Timeout::Error
      ].freeze

      def initialize(settings)
        @settings = settings
      end

      def render(prompt:, image_path:, camera:, options: {})
        endpoint = resolved_endpoint
        raise ArgumentError, 'API endpoint is empty.' if endpoint.empty?

        uri = URI(endpoint)
        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        api_key = @settings['api_key'].to_s.strip
        request['Authorization'] = "Bearer #{api_key}" unless api_key.empty?

        if request_mode == 'openai_image_edit_multipart'
          apply_multipart_body(request, openai_image_edit_fields(prompt, options), image_path)
        else
          request.body = JSON.generate(payload(prompt, image_path, camera, options))
        end

        response = perform(uri, request)
        body = response.body.to_s
        unless response.is_a?(Net::HTTPSuccess)
          raise "API request failed: HTTP #{response.code} #{body[0, 500]}"
        end

        parse_response(body)
      end

      def test_connection
        return test_models_endpoint if request_mode.start_with?('openai_image_edit')

        endpoint = resolved_endpoint
        raise ArgumentError, 'API endpoint is empty.' if endpoint.empty?

        uri = URI(endpoint)
        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        api_key = @settings['api_key'].to_s.strip
        request['Authorization'] = "Bearer #{api_key}" unless api_key.empty?
        request.body = JSON.generate(
          ping: true,
          model: @settings['model'].to_s,
          client: {
            name: EXTENSION_NAME,
            version: EXTENSION_VERSION
          }
        )

        response = perform(uri, request, read_timeout: 45)
        body = response.body.to_s
        if response.is_a?(Net::HTTPSuccess) || [400, 415, 422].include?(response.code.to_i)
          {
            ok: true,
            status: response.code.to_i,
            message: "API reached: HTTP #{response.code}",
            body_preview: body[0, 600]
          }
        else
          raise "API test failed: HTTP #{response.code} #{body[0, 600]}"
        end
      end

      def inspiration_plan(image_path:, note:, count:, references: [], text_model: 'gpt-5.5', include_images: true)
        endpoint = chat_completions_endpoint
        raise ArgumentError, 'Chat endpoint is empty.' if endpoint.empty?

        uri = URI(endpoint)
        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        api_key = chat_api_key
        request['Authorization'] = "Bearer #{api_key}" unless api_key.empty?
        request.body = JSON.generate(
          model: text_model,
          temperature: 0.35,
          response_format: { type: 'json_object' },
          messages: [
            {
              role: 'system',
              content: '你是建筑/室内设计灵感策划助理。必须只输出 JSON，不要输出 Markdown。'
            },
            {
              role: 'user',
              content: inspiration_plan_parts(image_path, note, count, references, include_images: include_images)
            }
          ]
        )

        response = perform(uri, request, read_timeout: 160)
        body = response.body.to_s
        unless response.is_a?(Net::HTTPSuccess)
          raise "Text model request failed: HTTP #{response.code} #{body[0, 500]}"
        end

        parse_text_json_response(body)
      end

      def inspiration_reference_analysis(base_image_path:, reference_image_path:, query:, intent:, version:, text_model: 'gpt-5.5', include_images: true)
        endpoint = chat_completions_endpoint
        raise ArgumentError, 'Chat endpoint is empty.' if endpoint.empty?

        uri = URI(endpoint)
        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        api_key = chat_api_key
        request['Authorization'] = "Bearer #{api_key}" unless api_key.empty?
        request.body = JSON.generate(
          model: text_model,
          temperature: 0.25,
          response_format: { type: 'json_object' },
          messages: [
            {
              role: 'system',
              content: '你是建筑/室内灵感图分析师。必须只输出 JSON，不要输出 Markdown。'
            },
            {
              role: 'user',
              content: inspiration_reference_analysis_parts(
                base_image_path,
                reference_image_path,
                query,
                intent,
                version,
                include_images: include_images
              )
            }
          ]
        )

        response = perform(uri, request, read_timeout: 160)
        body = response.body.to_s
        unless response.is_a?(Net::HTTPSuccess)
          raise "Reference analysis request failed: HTTP #{response.code} #{body[0, 500]}"
        end

        parse_text_json_response(body)
      end

      def inspiration_reference_batch_analysis(base_image_path:, references:, plan:, text_model: 'gpt-5.5', include_images: true)
        endpoint = chat_completions_endpoint
        raise ArgumentError, 'Chat endpoint is empty.' if endpoint.empty?

        uri = URI(endpoint)
        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        api_key = chat_api_key
        request['Authorization'] = "Bearer #{api_key}" unless api_key.empty?
        request.body = JSON.generate(
          model: text_model,
          temperature: 0.22,
          response_format: { type: 'json_object' },
          messages: [
            {
              role: 'system',
              content: '你是建筑/室内灵感图批量分析师。必须只输出 JSON，不要输出 Markdown。'
            },
            {
              role: 'user',
              content: inspiration_reference_batch_analysis_parts(base_image_path, references, plan, include_images: include_images)
            }
          ]
        )

        response = perform(uri, request, read_timeout: 180)
        body = response.body.to_s
        unless response.is_a?(Net::HTTPSuccess)
          raise "Reference batch analysis request failed: HTTP #{response.code} #{body[0, 500]}"
        end

        parse_text_json_response(body)
      end

      def test_chat_connection(text_model: 'gpt-5.5')
        endpoint = chat_completions_endpoint
        raise ArgumentError, 'Chat endpoint is empty.' if endpoint.empty?

        uri = URI(endpoint)
        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        api_key = chat_api_key
        request['Authorization'] = "Bearer #{api_key}" unless api_key.empty?
        request.body = JSON.generate(
          model: text_model,
          temperature: 0,
          response_format: { type: 'json_object' },
          messages: [
            {
              role: 'system',
              content: '只输出 JSON。'
            },
            {
              role: 'user',
              content: '返回 {"ok": true, "purpose": "connection_test"}'
            }
          ]
        )

        response = perform(uri, request, read_timeout: 45)
        body = response.body.to_s
        unless response.is_a?(Net::HTTPSuccess)
          raise "Text API test failed: HTTP #{response.code} #{body[0, 500]}"
        end

        {
          ok: true,
          status: response.code.to_i,
          model: text_model,
          endpoint: endpoint,
          message: "分析接口可用：HTTP #{response.code}"
        }
      end

      private

      def chat_completions_endpoint
        endpoint = @settings['text_endpoint'].to_s.strip
        endpoint = @settings['endpoint'].to_s.strip if endpoint.empty?
        return endpoint if endpoint.empty?

        uri = URI(endpoint)
        path = uri.path.to_s
        if path.empty? || path == '/'
          uri.path = '/v1/chat/completions'
        elsif path == '/v1' || path == '/v1/' || path.start_with?('/v1/')
          uri.path = '/v1/chat/completions'
        else
          uri.path = File.join(File.dirname(path), 'chat/completions')
        end
        uri.query = nil
        uri.to_s
      rescue URI::InvalidURIError
        endpoint
      end

      def chat_api_key
        key = @settings['text_api_key'].to_s.strip
        key.empty? ? @settings['api_key'].to_s.strip : key
      end

      def inspiration_plan_parts(image_path, note, count, references, include_images: true)
        text = <<~TEXT
          请先总结这张 SketchUp 白模截图的空间结构，再生成 #{count} 个 Pinterest 搜索词和 #{count} 个用于渲染白模的版本方向。

          用户灵感说明：#{note}

          流程要求：
          1. model_summary 必须总结截图里的空间类型、体块关系、开口/墙体/层高/动线、固定结构和相机视角。
          2. pinterest_queries 必须是适合复制到 Pinterest 搜索的英文查询词，每个查询词对应一个不同风格方向。
          3. versions 必须反向总结 Pinterest 灵感图常见的材质、灯光、配色、软装和氛围，用于后续 image-2 渲染。
          4. 每个版本都要给出 key_points，用于在灵感图上标注 3-4 个关键设计点。
          5. 所有版本都必须强调保持原白模视角和结构，只替换材质、灯光、家具表皮、软装和氛围。

          只输出以下 JSON 结构：
          {
            "model_summary": "中文白模结构总结",
            "pinterest_queries": [
              {"index": 1, "query": "english pinterest search query", "intent": "中文说明这个搜索词想找什么灵感"}
            ],
            "versions": [
              {
                "index": 1,
                "title": "中文版本名",
                "style_summary": "中文风格摘要",
                "render_prompt": "中文渲染提示词",
                "key_points": [
                  {"label": "短标签", "detail": "说明材质/灯光/配色/陈列等关键点"}
                ]
              }
            ]
          }
        TEXT

        parts = [{ type: 'text', text: text }]
        if include_images
          parts << image_part(image_path)
          Array(references).first(4).each do |reference|
            path = reference.is_a?(Hash) ? reference['path'].to_s : ''
            parts << image_part(path) if File.file?(path)
          end
        else
          parts << {
            type: 'text',
            text: '注意：本轮规划模型不支持图片输入。请根据用户灵感说明生成安全的 Pinterest 搜索词和版本方向；所有版本必须严格保留原 SketchUp 白模截图的结构、视角和空间关系，后续渲染仍会以白模截图作为基础图。'
          }
        end
        parts
      end

      def inspiration_reference_analysis_parts(base_image_path, reference_image_path, query, intent, version, include_images: true)
        text = <<~TEXT
          请分析这张 Pinterest 灵感图，并结合 SketchUp 白模截图，输出可用于把白模渲染成同类效果的结构化灵感。

          Pinterest 搜索词：#{query}
          搜索意图：#{intent}
          版本方向：#{version.is_a?(Hash) ? version['render_prompt'].to_s : version.to_s}

          要求：
          1. extracted_prompt 是给 image-2/gpt-image-2 使用的中文渲染提示词，只描述可迁移到白模上的材质、灯光、配色、软装、陈列和氛围，不允许改变白模结构。
          2. key_points 从 Pinterest 灵感图中提取 3-4 个关键点。每个点必须包含 label、detail、x、y；x/y 是在灵感图上的百分比位置，范围 5-95，便于界面打点标注。
          3. summary 用中文概括这张灵感图值得借鉴的核心。
          4. 不要编造品牌、设计师或项目出处。

          只输出以下 JSON：
          {
            "summary": "中文灵感图摘要",
            "extracted_prompt": "中文反推提示词",
            "key_points": [
              {"label": "短标签", "detail": "关键点说明", "x": 35, "y": 42}
            ]
          }
        TEXT

        parts = [{ type: 'text', text: text }]
        if include_images
          parts << { type: 'text', text: '下面第一张是 SketchUp 白模基础图，第二张是 Pinterest 灵感图。' }
          parts << image_part(base_image_path) if File.file?(base_image_path.to_s)
          parts << image_part(reference_image_path)
        else
          parts << {
            type: 'text',
            text: '注意：本轮模型不支持图片输入。请只依据搜索词、搜索意图和版本方向提炼可迁移的材质、灯光、配色、软装与氛围，不要声称看到了图片细节。key_points 使用通用构图位置。'
          }
        end
        parts
      end

      def inspiration_reference_batch_analysis_parts(base_image_path, references, plan, include_images: true)
        references = Array(references).select { |item| item.is_a?(Hash) && File.file?(item['path'].to_s) }.first(12)
        version_map = {}
        Array(plan.is_a?(Hash) ? plan['versions'] : []).each do |item|
          next unless item.is_a?(Hash)

          version_map[item['index'].to_i] = item
        end

        manifest = references.map do |reference|
          index = reference['index'].to_i
          version = version_map[index] || {}
          {
            index: index,
            query: reference['query'].to_s,
            intent: reference['intent'].to_s,
            version_direction: version['render_prompt'].to_s.empty? ? version['style_summary'].to_s : version['render_prompt'].to_s
          }
        end

        text = <<~TEXT
          请批量分析 Pinterest 灵感图，并结合 SketchUp 白模截图，输出可用于把白模渲染成同类效果的结构化灵感。

          第一张图片是 SketchUp 白模基础图，后续每张图片前都有对应参考图编号。参考图清单：
          #{JSON.pretty_generate(manifest)}

          要求：
          1. analyses 必须按参考图编号返回，每个参考图一个对象。
          2. extracted_prompt 是给 image-2/gpt-image-2 使用的中文渲染提示词，只描述可迁移到白模上的材质、灯光、配色、软装、陈列和氛围，不允许改变白模结构。
          3. key_points 从对应 Pinterest 灵感图中提取 3-4 个关键点。每个点必须包含 label、detail、x、y；x/y 是在该灵感图上的百分比位置，范围 5-95，便于界面打点标注。
          4. summary 用中文概括该灵感图值得借鉴的核心。
          5. 不要编造品牌、设计师或项目出处。

          只输出以下 JSON：
          {
            "analyses": [
              {
                "index": 1,
                "summary": "中文灵感图摘要",
                "extracted_prompt": "中文反推提示词",
                "key_points": [
                  {"label": "短标签", "detail": "关键点说明", "x": 35, "y": 42}
                ]
              }
            ]
          }
        TEXT

        parts = [{ type: 'text', text: text }]
        if include_images
          parts << { type: 'text', text: '下面第一张是 SketchUp 白模基础图。' }
          parts << image_part(base_image_path, 'low') if File.file?(base_image_path.to_s)
          references.each do |reference|
            parts << { type: 'text', text: "下面是 Pinterest 参考图 index=#{reference['index']}，搜索词：#{reference['query']}，搜索意图：#{reference['intent']}" }
            parts << image_part(reference['path'].to_s, 'low')
          end
        else
          parts << {
            type: 'text',
            text: '注意：本轮模型不支持图片输入。请只依据参考图清单、Pinterest 搜索词、搜索意图和版本方向，为每个 index 输出可用于渲染白模的提示词；不要声称看到了图片细节。key_points 使用通用构图位置。'
          }
        end
        parts
      end

      def image_part(path, detail = 'high')
        {
          type: 'image_url',
          image_url: {
            url: "data:#{mime_type(path)};base64,#{Base64.strict_encode64(File.binread(path))}",
            detail: detail
          }
        }
      end

      def parse_text_json_response(body)
        json = JSON.parse(body)
        content = json.dig('choices', 0, 'message', 'content')
        content = json.dig('choices', 0, 'text') if content.to_s.empty?
        content = json['output_text'] if content.to_s.empty?
        if content.to_s.empty? && json['output'].is_a?(Array)
          content = json['output'].flat_map { |item| item['content'] if item.is_a?(Hash) }.compact.flatten.map do |item|
            item.is_a?(Hash) ? (item['text'] || item['content']) : item
          end.compact.join("\n")
        end
        JSON.parse(extract_json_text(content.to_s))
      end

      def extract_json_text(text)
        clean = text.strip
        clean = clean.sub(/\A```(?:json)?\s*/i, '').sub(/\s*```\z/, '').strip
        first = clean.index('{')
        last = clean.rindex('}')
        return clean if first.nil? || last.nil? || last < first

        clean[first..last]
      end

      def test_models_endpoint
        endpoint = models_endpoint
        raise ArgumentError, 'API endpoint is empty.' if endpoint.empty?

        uri = URI(endpoint)
        request = Net::HTTP::Get.new(uri)
        api_key = @settings['api_key'].to_s.strip
        request['Authorization'] = "Bearer #{api_key}" unless api_key.empty?

        response = perform(uri, request, read_timeout: 45)
        body = response.body.to_s
        unless response.is_a?(Net::HTTPSuccess)
          raise "API test failed: HTTP #{response.code} #{body[0, 600]}"
        end

        model_count, image_models = summarize_models(body)
        preview = image_models.empty? ? body[0, 600] : "image models: #{image_models.join(', ')}"
        {
          ok: true,
          status: response.code.to_i,
          message: "API reached: HTTP #{response.code}, #{model_count} models visible",
          body_preview: preview
        }
      rescue JSON::ParserError
        {
          ok: true,
          status: response.code.to_i,
          message: "API reached: HTTP #{response.code}, non-JSON models response",
          body_preview: body[0, 600]
        }
      end

      def models_endpoint
        endpoint = @settings['endpoint'].to_s.strip
        return endpoint if endpoint.empty?

        uri = URI(endpoint)
        path = uri.path.to_s
        if path.empty? || path == '/'
          uri.path = '/v1/models'
        elsif path == '/v1' || path == '/v1/' || path.start_with?('/v1/images/')
          uri.path = '/v1/models'
        else
          uri.path = File.join(File.dirname(path), 'models')
        end
        uri.query = nil
        uri.to_s
      rescue URI::InvalidURIError
        endpoint
      end

      def summarize_models(body)
        json = JSON.parse(body)
        items = json['data'].is_a?(Array) ? json['data'] : []
        ids = items.map { |item| item.is_a?(Hash) ? item['id'].to_s : item.to_s }.reject(&:empty?)
        image_ids = ids.select { |id| id =~ /image|banana|dall|flux|mj|midjourney|jimeng|gemini/i }
        [ids.length, image_ids.first(12)]
      end

      def resolved_endpoint
        endpoint = @settings['endpoint'].to_s.strip
        return endpoint if endpoint.empty?
        return endpoint unless request_mode.start_with?('openai_image_edit')

        uri = URI(endpoint)
        path = uri.path.to_s
        normalized_path = path.empty? ? '/' : path

        if normalized_path == '/' || normalized_path == '/v1' || normalized_path == '/v1/'
          uri.path = '/v1/images/edits'
          uri.query = nil
          uri.to_s
        else
          endpoint
        end
      rescue URI::InvalidURIError
        endpoint
      end

      def payload(prompt, image_path, camera, options)
        if request_mode == 'openai_image_edit_json'
          return openai_image_edit_payload(prompt, image_path, options)
        end

        {
          prompt: prompt,
          model: @settings['model'].to_s,
          source: {
            type: 'sketchup_view',
            image: {
              filename: File.basename(image_path),
              mime_type: mime_type(image_path),
              data: Base64.strict_encode64(File.binread(image_path))
            },
            camera: camera
          },
          options: reject_nil({
            strength: options['strength'],
            guidance: options['guidance'],
            size: options['size']
          }),
          client: {
            name: EXTENSION_NAME,
            version: EXTENSION_VERSION
          }
        }
      end

      def request_mode
        mode = @settings['request_mode'].to_s.strip
        mode.empty? ? 'custom_json' : mode
      end

      def openai_image_edit_payload(prompt, image_path, options)
        data_url = "data:#{mime_type(image_path)};base64,#{Base64.strict_encode64(File.binread(image_path))}"
        payload = {
          model: @settings['model'].to_s.empty? ? 'gpt-image-2' : @settings['model'].to_s,
          prompt: effective_prompt(prompt),
          images: [
            {
              image_url: data_url
            }
          ]
        }

        size = openai_size(options['size'])
        payload[:size] = size if size
        payload
      end

      def openai_image_edit_fields(prompt, options)
        fields = {
          'model' => @settings['model'].to_s.empty? ? 'gpt-image-2' : @settings['model'].to_s,
          'prompt' => effective_prompt(prompt)
        }
        fields['size'] = openai_size(options['size']) || 'auto'
        fields
      end

      def effective_prompt(prompt)
        text = prompt.to_s.strip
        return text unless text.empty?

        '将这张 SketchUp 模型截图转化为高质量写实建筑/室内/景观效果图，保持原始模型构图、空间关系和相机视角，补充真实材质、自然光影、细节纹理和照片级质感。'
      end

      def apply_multipart_body(request, fields, image_path)
        boundary = "----LLGHDLocalAIRender#{Time.now.to_i}#{rand(1_000_000)}"
        body = ''.b
        fields.each do |name, value|
          body << binary_text("--#{boundary}\r\n")
          body << binary_text("Content-Disposition: form-data; name=\"#{name}\"\r\n\r\n")
          body << binary_text(value)
          body << binary_text("\r\n")
        end

        body << binary_text("--#{boundary}\r\n")
        body << binary_text("Content-Disposition: form-data; name=\"image\"; filename=\"#{multipart_filename(image_path)}\"\r\n")
        body << binary_text("Content-Type: #{mime_type(image_path)}\r\n\r\n")
        body << File.binread(image_path).force_encoding(Encoding::BINARY)
        body << binary_text("\r\n--#{boundary}--\r\n")

        request['Content-Type'] = "multipart/form-data; boundary=#{boundary}"
        request.body = body
      end

      def binary_text(value)
        value.to_s.encode('UTF-8').dup.force_encoding(Encoding::BINARY)
      end

      def multipart_filename(path)
        File.basename(path).encode('UTF-8', invalid: :replace, undef: :replace, replace: '_')
      end

      def openai_size(size)
        value = size.to_s.strip
        return nil if value.empty?
        return value if %w[1024x1024 1536x1024 1024x1536 auto].include?(value)

        nil
      end

      def perform(uri, request, read_timeout: 300)
        begin
          return perform_once(uri, request, read_timeout: read_timeout, use_env_proxy: false)
        rescue Net::ReadTimeout => e
          raise network_error(e)
        rescue *CONNECTION_ERRORS => e
          raise network_error(e) unless proxy_env_present?

          direct_error = e
        end

        begin
          perform_once(uri, request, read_timeout: read_timeout, use_env_proxy: true)
        rescue Net::ReadTimeout => e
          raise network_error(e, previous_error: direct_error)
        rescue *CONNECTION_ERRORS => e
          raise network_error(e, previous_error: direct_error)
        end
      end

      def perform_once(uri, request, read_timeout:, use_env_proxy:)
        http = if use_env_proxy
                 Net::HTTP.new(uri.host, uri.port)
               else
                 Net::HTTP.new(uri.host, uri.port, nil)
               end
        http.use_ssl = uri.scheme == 'https'
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.open_timeout = 25
        http.read_timeout = read_timeout
        http.request(request)
      end

      def proxy_env_present?
        %w[HTTPS_PROXY https_proxy HTTP_PROXY http_proxy ALL_PROXY all_proxy].any? do |key|
          !ENV[key].to_s.strip.empty?
        end
      end

      def network_error(error, previous_error: nil)
        message = error.message.to_s
        combined = if previous_error
                     "direct #{previous_error.class}: #{previous_error.message}; proxy #{error.class}: #{message}"
                   else
                     "#{error.class}: #{message}"
                   end
        hint = if proxy_env_present?
                 '网络连接失败。插件已改为先直连接口，直连无法打开时再尝试系统代理；如果仍失败，请检查接口地址或本机代理 127.0.0.1:7897。'
               else
                 '网络连接失败，请检查接口地址、网络和证书链。'
               end
        RuntimeError.new("#{hint} 原始错误：#{combined}")
      end

      def reject_nil(hash)
        hash.reject { |_key, value| value.nil? || value.to_s.empty? }
      end

      def parse_response(body)
        json = body.empty? ? {} : JSON.parse(body)

        if (image = first_image(json))
          return normalize_image(image)
        end

        {
          response: json,
          message: json['message'] || 'Render request completed, but no image field was found.'
        }
      rescue JSON::ParserError
        {
          raw_response: body,
          message: 'Render request completed with a non-JSON response.'
        }
      end

      def first_image(json)
        return json['image'] if json['image'].is_a?(Hash)
        return { 'url' => json['image_url'] } if json['image_url']
        return { 'data' => json['image_base64'], 'mime_type' => json['mime_type'] } if json['image_base64']

        images = json['images']
        return images.first if images.is_a?(Array) && images.first.is_a?(Hash)

        data = json['data']
        if data.is_a?(Array) && data.first.is_a?(Hash)
          item = data.first
          return { 'url' => item['url'] } if item['url']
          if item['b64_json']
            mime = "image/#{item['output_format'] || json['output_format'] || 'png'}"
            return { 'data' => item['b64_json'], 'mime_type' => mime }
          end
        end

        nil
      end

      def normalize_image(image)
        if image['url']
          {
            image_url: image['url'],
            response: image
          }
        elsif image['data']
          path = save_base64_image(image['data'], image['mime_type'] || 'image/png')
          {
            image_path: path,
            image_url: LocalAIRender.file_url(path),
            response: image.reject { |key, _| key == 'data' }
          }
        else
          {
            response: image,
            message: 'Image object did not include url or base64 data.'
          }
        end
      end

      def save_base64_image(encoded, mime)
        ext = mime.include?('jpeg') ? 'jpg' : mime.split('/').last.to_s.gsub(/[^a-z0-9]/i, '')
        ext = 'png' if ext.empty?
        dir = File.join(LocalAIRender.output_root, 'renders')
        FileUtils.mkdir_p(dir)
        path = File.join(dir, "render-#{LocalAIRender.timestamp}.#{ext}")
        File.binwrite(path, Base64.decode64(encoded.to_s))
        path
      end

      def mime_type(path)
        case File.extname(path).downcase
        when '.jpg', '.jpeg'
          'image/jpeg'
        when '.webp'
          'image/webp'
        else
          'image/png'
        end
      end
    end
  end
end
