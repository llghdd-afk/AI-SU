# encoding: utf-8
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  AI建模助手 - SketchUp AI建模插件 (AI+SU 单文件版)
#  通过自然语言与AI对话，生成Ruby代码在SketchUp中建模
#  支持: 通义千问 / Kimi / Gemini / DeepSeek / 小米TokenPlan / Codex CLI中转站 / 自定义OpenAI兼容API
#  版本: 1.2.0 - 三阶段工作流 + 图像理解 + 文生图 + 代码控制台
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

require 'sketchup.rb'
require 'net/http'
require 'uri'
require 'json'
require 'base64'

module AiDialogAssistant

  PLUGIN_ID   = 'ai_su'.freeze
  PLUGIN_NAME = 'AI建模助手'.freeze
  PLUGIN_VER  = '1.2.0'.freeze

  # ━━━━━━━━━━━━━━━━ 配置管理 ━━━━━━━━━━━━━━━━
  module Config
    DEFAULTS = {
      'api_url'        => 'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
      'api_key'        => '',
      'model'          => 'qwen-coder-plus-latest',
      'max_tokens'     => 4096,
      'temperature'    => 0.3,
      'auto_execute'   => false,
      'provider'       => 'qwen',
      'image_api_url'  => 'https://dashscope.aliyuncs.com/compatible-mode/v1/images/generations',
      'image_api_key'  => '',
      'image_model'    => 'wanx2.1-t2i-turbo',
      'image_provider' => 'qwen'
    }.freeze

    PROVIDERS = {
      'qwen' => {
        'name'           => '通义千问(百炼)',
        'chat_url'       => 'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
        'models_url'     => 'https://dashscope.aliyuncs.com/compatible-mode/v1/models',
        'api_mode'       => 'chat_completions',
        'image_url'      => 'https://dashscope.aliyuncs.com/compatible-mode/v1/images/generations',
        'default_model'  => 'qwen-coder-plus-latest',
        'image_models'   => ['wanx2.1-t2i-turbo', 'wanx-v1']
      },
      'kimi' => {
        'name'           => 'Kimi(月之暗面)',
        'chat_url'       => 'https://api.moonshot.cn/v1/chat/completions',
        'models_url'     => 'https://api.moonshot.cn/v1/models',
        'api_mode'       => 'chat_completions',
        'image_url'      => '',
        'default_model'  => 'moonshot-v1-128k',
        'image_models'   => []
      },
      'gemini' => {
        'name'           => 'Google Gemini',
        'chat_url'       => 'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
        'models_url'     => 'https://generativelanguage.googleapis.com/v1beta/openai/models',
        'api_mode'       => 'chat_completions',
        'image_url'      => '',
        'default_model'  => 'gemini-2.0-flash',
        'image_models'   => []
      },
      'deepseek' => {
        'name'           => 'DeepSeek',
        'chat_url'       => 'https://api.deepseek.com/v1/chat/completions',
        'models_url'     => 'https://api.deepseek.com/v1/models',
        'api_mode'       => 'chat_completions',
        'image_url'      => '',
        'default_model'  => 'deepseek-chat',
        'image_models'   => []
      },
      'xiaomi_tokenplan' => {
        'name'            => '小米 TokenPlan',
        'chat_url'        => 'https://token-plan-cn.xiaomimimo.com/v1/chat/completions',
        'models_url'      => 'https://token-plan-cn.xiaomimimo.com/v1/models',
        'api_mode'        => 'chat_completions',
        'image_detail'    => 'high',
        'image_url'       => '',
        'default_model'   => 'mimo-v2.5-pro',
        'fallback_models' => ['mimo-v2.5-pro', 'mimo-v2.5', 'mimo-v2-pro', 'mimo-v2-omni'],
        'image_models'    => []
      },
      'codex_cli_relay' => {
        'name'                     => 'Codex CLI 中转站',
        'chat_url'                 => 'https://www.hd1100.cc',
        'models_url'               => '',
        'api_mode'                 => 'responses',
        'image_detail'             => 'high',
        'image_url'                => '',
        'default_model'            => 'gpt-5.4',
        'fallback_models'          => ['gpt-5.4', 'gpt-5.5', 'gpt-5'],
        'reasoning_effort'         => 'high',
        'disable_response_storage' => true,
        'image_models'             => []
      },
      'custom' => {
        'name'           => '自定义(OpenAI兼容)',
        'chat_url'       => '',
        'models_url'     => '',
        'api_mode'       => 'chat_completions',
        'image_url'      => '',
        'default_model'  => '',
        'image_models'   => []
      }
    }.freeze

    def self.get(key)
      Sketchup.read_default(PLUGIN_ID, key) || DEFAULTS[key]
    end

    def self.set(key, value)
      Sketchup.write_default(PLUGIN_ID, key, value)
    end

    def self.get_all
      result = {}
      DEFAULTS.each_key { |k| result[k] = get(k) }
      result
    end

    def self.set_all(hash)
      hash.each { |k, v| set(k, v) }
    end

    def self.provider_config(provider_name = provider)
      PROVIDERS[provider_name.to_s] || PROVIDERS['custom']
    end

    def self.provider_api_mode(provider_name = provider)
      provider_config(provider_name)['api_mode'] || 'chat_completions'
    end

    def self.image_detail
      provider_config['image_detail'] || 'high'
    end

    def self.api_url
      configured_url = get('api_url').to_s.strip
      default_url = provider_config['chat_url'].to_s
      configured_url = '' if stale_provider_default_url?(configured_url)
      normalize_api_url(configured_url.empty? ? default_url : configured_url, provider_api_mode)
    end

    def self.api_key;              get('api_key');           end
    def self.model;                get('model');             end
    def self.image_api_url;        get('image_api_url');     end
    def self.image_api_key;        get('image_api_key');     end
    def self.image_model;          get('image_model');       end
    def self.provider;             get('provider');          end
    def self.responses_api?;        provider_api_mode == 'responses'; end

    def self.stale_provider_default_url?(api_url)
      return false if api_url.nil? || api_url.empty?

      current_default = provider_config['chat_url'].to_s
      return false if api_url == current_default

      PROVIDERS.any? do |_name, config|
        default_url = config['chat_url'].to_s
        !default_url.empty? && api_url == default_url
      end
    end

    def self.normalize_api_url(api_url, api_mode)
      return api_url if api_url.nil? || api_url.empty?

      uri = URI.parse(api_url)
      path = uri.path.to_s

      if api_mode == 'responses'
        if path.empty? || path == '/'
          uri.path = '/v1/responses'
        elsif path.end_with?('/v1')
          uri.path = "#{path}/responses"
        elsif path.end_with?('/chat/completions')
          uri.path = path.sub(/\/chat\/completions$/, '/responses')
        elsif !path.end_with?('/responses')
          uri.path = "#{path.sub(/\/$/, '')}/responses"
        end
      elsif path.empty? || path == '/'
        uri.path = '/v1/chat/completions'
      elsif path.end_with?('/v1')
        uri.path = "#{path}/chat/completions"
      end

      uri.to_s
    rescue StandardError
      api_url
    end

    def self.vision_capable?
      provider_name = provider.to_s
      model_name = model.to_s.downcase
      return false if provider_name == 'deepseek'
      return true if provider_name == 'codex_cli_relay' && model_name.match?(/(gpt-5|gpt-4o|gpt-4\.1|vision|omni)/)
      return true if provider_name == 'gemini'
      return true if ['qwen', 'xiaomi_tokenplan'].include?(provider_name) && model_name.match?(/(vl|omni|vision|qvq|mimo-v2\.5$|mimo-v2-omni)/)
      return true if provider_name == 'custom' && model_name.match?(/(vision|vl|gpt-5|gpt-4o|gpt-4\.1|gemini|claude-3)/)

      false
    end

    def self.vision_status_message
      provider_label = PROVIDERS.dig(provider.to_s, 'name') || provider.to_s
      "当前模型（#{provider_label} / #{model}）不支持图片消息，已改用文字上下文分析。若需要识别截图或参考图，请切换到支持视觉的模型，例如 Gemini、Qwen-VL 或自定义视觉模型。"
    end

    def self.system_prompt
      <<~PROMPT
        你是一个SketchUp建模AI助手，帮助用户通过自然语言进行3D建模设计。

        ## 工作流程

        ### 第一阶段：方案沟通
        当用户描述一个设计需求时：
        1. 用自然语言讨论和确认设计意图、风格、功能需求
        2. 如果用户想要查看效果，提示用户可以点击"生成效果图"按钮生成概念效果图
        3. 不要在这个阶段生成代码

        ### 第二阶段：尺寸确认
        当用户同意方案后：
        1. 列出所有关键设计参数（长、宽、高、间距、倒角、厚度等）
        2. 为每个参数提供默认建议值（或根据用户描述推算）
        3. 让用户逐一确认或修改这些参数
        4. 不要在这个阶段生成代码

        ### 第三阶段：代码生成
        当用户确认所有尺寸参数后：
        1. 生成完整的SketchUp Ruby代码
        2. 代码用```ruby和```包裹
        3. 代码会自动显示在下方的Ruby控制台

        ## 生成前沟通规则
        1. 除非用户明确说“生成代码”“建模”“执行”“尺寸都确认”，不要直接输出Ruby代码。
        2. 如果需求缺少尺寸、结构、摆放位置、材质或风格，先主动提出3-6个关键问题。
        3. 如果用户粘贴了参考图但当前模型不支持视觉输入，请用户用文字补充参考图中的关键造型、尺寸比例、材质和装配关系。
        4. 如果用户要求快速生成，可以给出合理默认值，但仍要先列出默认参数并征求确认。
        5. 如果用户提供效果图/参考图并要求“按图建模”，先识别图中的主体形态、比例、构件层级、材质和可建模特征；缺少真实尺寸时给出合理默认尺寸并询问确认，用户明确要求直接生成时才输出Ruby代码。
        6. 如果用户提供当前SketchUp截图并要求修改，先指出截图中可见的问题（漂浮、错位、散件、门窗未贴墙、比例不协调等），再生成只针对现有模型修正的Ruby代码，尽量保留已有对象。

        ## 代码规范

        ### 创建基本几何体
        ```ruby
        # 创建矩形面并推拉
        face = entities.add_face([0,0,0], [10.m,0,0], [10.m,8.m,0], [0,8.m,0])
        face.pushpull(-3.m)

        # 创建组
        group = entities.add_group
        grp_ents = group.entities
        face = grp_ents.add_face(pts)
        face.pushpull(-h)

        # 创建圆
        center = Geom::Point3d.new(0, 0, 0)
        normal = Geom::Vector3d.new(0, 0, 1)
        edges = entities.add_circle(center, normal, radius)
        face = entities.add_face(edges)

        # 创建圆柱体
        group = entities.add_group
        circle = group.entities.add_circle(center, Z_AXIS, radius, 24)
        face = group.entities.add_face(circle)
        face.pushpull(-height)
        ```

        ### 变换操作
        ```ruby
        # 移动
        tr = Geom::Transformation.new([x, y, z])
        entities.transform_entities(tr, entity)

        # 旋转
        tr = Geom::Transformation.rotation(point, axis, angle.degrees)
        entities.transform_entities(tr, entity)

        # 缩放
        tr = Geom::Transformation.scaling(factor)
        entities.transform_entities(tr, entity)
        ```

        ### 材质与颜色
        ```ruby
        face.material = Sketchup::Color.new(255, 0, 0)
        mat = model.materials.add("自定义材质")
        mat.color = Sketchup::Color.new(200, 180, 160)
        mat.alpha = 0.5
        face.material = mat
        ```

        ### 组件操作
        ```ruby
        defn = model.definitions.add("组件名")
        defn.entities.add_face(...)
        instance = entities.add_instance(defn, transformation)
        ```

        ### 曲面
        ```ruby
        mesh = Geom::PolygonMesh.new
        mesh.add_point(pt1)
        mesh.add_point(pt2)
        mesh.add_point(pt3)
        mesh.add_polygon(1, 2, 3)
        group = entities.add_group
        group.entities.fill_from_mesh(mesh, true, 0)
        ```

        ## 重要规则
        1. 只生成纯Ruby代码，在方案沟通和参数确认阶段不要生成代码
        2. 代码必须可以在SketchUp的Ruby控制台中直接执行
        3. 使用 `model = Sketchup.active_model` 和 `entities = model.active_entities` 开头
        4. 所有操作包裹在 `model.start_operation('操作名', true)` 和 `model.commit_operation` 中
        5. 长度单位默认使用米(m)，例如 `3.m` 表示3米
        6. 代码中不要使用 `require` 语句
        7. 不要访问文件系统或网络
        8. 代码中要有清晰的中文注释，说明每步在做什么
        9. 所有新增几何必须放入一个顶层Group或Component中，命名为清晰的中文名称，例如 `ai_model = entities.add_group`，再在 `ai_model.entities` 中创建零件。
        10. 大件、零件、柱子、桌面、椅背等必须按真实装配关系放置在同一坐标系内，不能散落在模型空间中。
        11. 如果需要多个部件，应在顶层Group内部再创建子Group或Component，最终只让用户看到一个可移动、可选择的整体对象。
        12. 生成结束后选中顶层Group或Component，并执行 `model.active_view.zoom_extents`。
      PROMPT
    end
  end

  # ━━━━━━━━━━━━━━━━ 文生图模块 ━━━━━━━━━━━━━━━━
  module ImageGen
    def self.generate(prompt, api_url, api_key, image_model)
      return { 'error' => true, 'message' => '未配置文生图API' } if api_url.nil? || api_url.empty?

      uri = URI.parse(api_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = 15
      http.read_timeout = 60

      # 尝试 OpenAI 兼容格式（推荐）
      body = {
        'model'  => image_model || 'wanx2.1-t2i-turbo',
        'prompt' => prompt,
        'n'      => 1,
        'size'   => '1024x1024'
      }

      request = Net::HTTP::Post.new(uri.request_uri)
      request['Content-Type'] = 'application/json'
      request['Authorization'] = "Bearer #{api_key}"
      request.body = JSON.generate(body)

      response = http.request(request)

      if response.code.to_i == 200
        result = JSON.parse(response.body)
        # 处理不同格式的响应
        img_url = result.dig('data', 0, 'url') || result.dig('output', 'results', 0, 'url') || ''
        img_b64 = result.dig('data', 0, 'b64_json') || ''

        if !img_b64.empty?
          return { 'error' => false, 'image_b64' => img_b64 }
        elsif !img_url.empty?
          return { 'error' => false, 'image_url' => img_url }
        else
          return { 'error' => true, 'message' => '无法解析图片结果' }
        end
      else
        { 'error' => true, 'message' => "生成失败: HTTP #{response.code}" }
      end
    rescue StandardError => e
      { 'error' => true, 'message' => "文生图错误: #{e.message}" }
    end
  end

  # ━━━━━━━━━━━━━━━━ API模型获取 ━━━━━━━━━━━━━━━━
  module ModelFetcher
    def self.fetch_models(api_url, api_key, provider = nil)
      provider_config = Config.provider_config(provider)
      models_url = provider_config['models_url'].to_s
      models_url = derive_models_url(api_url, provider_config['api_mode']) if models_url.empty?

      uri = URI.parse(models_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = 10
      http.read_timeout = 15

      request = Net::HTTP::Get.new(uri.request_uri)
      request['Authorization'] = "Bearer #{api_key}"

      response = http.request(request)
      if response.code.to_i == 200
        data = JSON.parse(response.body)
        models = data['data'].map { |m| m['id'] }.sort rescue []
        models = fallback_models(provider_config) if models.empty?
        { 'error' => false, 'models' => models }
      else
        if [404, 405].include?(response.code.to_i)
          fallback = fallback_models(provider_config)
          return { 'error' => false, 'models' => fallback } unless fallback.empty?
        end

        { 'error' => true, 'message' => "HTTP #{response.code}" }
      end
    rescue StandardError => e
      { 'error' => true, 'message' => e.message }
    end

    def self.derive_models_url(api_url, api_mode)
      normalized_url = Config.normalize_api_url(api_url.to_s, api_mode || 'chat_completions')
      uri = URI.parse(normalized_url)
      path = uri.path.to_s

      uri.path =
        if path.end_with?('/chat/completions')
          path.sub(/\/chat\/completions$/, '/models')
        elsif path.end_with?('/responses')
          path.sub(/\/responses$/, '/models')
        elsif path.end_with?('/v1')
          "#{path}/models"
        else
          "#{path.sub(/\/$/, '')}/models"
        end

      uri.to_s
    rescue StandardError
      api_url.to_s.sub(/\/chat\/completions$/, '/models').sub(/\/responses$/, '/models')
    end

    def self.fallback_models(provider_config)
      models = Array(provider_config['fallback_models'])
      default_model = provider_config['default_model'].to_s
      models.unshift(default_model) unless default_model.empty? || models.include?(default_model)
      models
    end
  end

  # ━━━━━━━━━━━━━━━━ API通信 ━━━━━━━━━━━━━━━━
  module ApiClient
    @conversation_history = []

    def self.conversation_history
      @conversation_history
    end

    def self.clear_history
      @conversation_history = []
    end

    def self.chat(user_message)
      api_key = Config.api_key
      return { 'error' => true, 'message' => '请先在设置中配置API Key' } if api_key.nil? || api_key.empty?

      messages = [{ 'role' => 'system', 'content' => Config.system_prompt }]
      messages.concat(@conversation_history.last(20))
      messages << { 'role' => 'user', 'content' => user_message }

      body = {
        'model'       => Config.model,
        'messages'    => messages,
        'max_tokens'  => Config.get('max_tokens').to_i,
        'temperature' => Config.get('temperature').to_f,
        'stream'      => false
      }

      begin
        response = send_request(Config.api_url, api_key, body)
        return response if response['error']

        content = extract_content(response)
        @conversation_history << { 'role' => 'user', 'content' => user_message }
        @conversation_history << { 'role' => 'assistant', 'content' => content }
        @conversation_history = @conversation_history.last(40) if @conversation_history.length > 40

        { 'error' => false, 'content' => content }
      rescue StandardError => e
        { 'error' => true, 'message' => "API请求失败: #{e.message}" }
      end
    end

    def self.chat_with_context(user_message, context_text)
      context_message = <<~TEXT
        #{user_message}

        [插件提供的上下文]
        #{context_text}
      TEXT
      chat(context_message)
    end

    def self.chat_with_reference_images(user_message, references_json)
      api_key = Config.api_key
      return { 'error' => true, 'message' => '请先在设置中配置API Key' } if api_key.nil? || api_key.empty?

      references = JSON.parse(references_json) rescue []
      return chat(user_message) if references.empty?

      unless Config.vision_capable?
        names = references.map { |ref| ref['name'] || '参考图' }.join('、')
        context = <<~TEXT
          #{Config.vision_status_message}
          用户在输入框粘贴了 #{references.length} 张参考图：#{names}。
          当前模型无法读取图片内容。请先让用户用文字补充参考图里的关键造型、尺寸比例、材质、连接方式和希望保留的细节；在参数确认前不要直接生成Ruby代码。
        TEXT
        return chat_with_context(user_message, context)
      end

      messages = [{ 'role' => 'system', 'content' => Config.system_prompt }]
      messages.concat(@conversation_history.last(10))

      user_content = [{ 'type' => 'text', 'text' => user_message }]
      references.first(3).each do |ref|
        data_url = ref['data_url'].to_s
        next if data_url.empty?
        user_content << { 'type' => 'image_url', 'image_url' => { 'url' => data_url, 'detail' => Config.image_detail } }
      end
      messages << { 'role' => 'user', 'content' => user_content }

      body = {
        'model'       => Config.model,
        'messages'    => messages,
        'max_tokens'  => Config.get('max_tokens').to_i,
        'temperature' => Config.get('temperature').to_f,
        'stream'      => false
      }

      begin
        response = send_request(Config.api_url, api_key, body)
        return response if response['error']

        content = extract_content(response)
        @conversation_history << { 'role' => 'user', 'content' => "[参考图 #{references.length}张] #{user_message}" }
        @conversation_history << { 'role' => 'assistant', 'content' => content }

        { 'error' => false, 'content' => content }
      rescue StandardError => e
        { 'error' => true, 'message' => "API请求失败: #{e.message}" }
      end
    end

    def self.chat_with_image(user_message, image_base64)
      api_key = Config.api_key
      return { 'error' => true, 'message' => '请先在设置中配置API Key' } if api_key.nil? || api_key.empty?

      unless Config.vision_capable?
        context = <<~TEXT
          #{Config.vision_status_message}
          当前SketchUp模型结构：
          #{CodeExecutor.model_context rescue '无法读取当前模型结构。'}
        TEXT
        return chat_with_context(user_message, context)
      end

      messages = [{ 'role' => 'system', 'content' => Config.system_prompt }]
      messages.concat(@conversation_history.last(10))

      user_content = [
        { 'type' => 'text', 'text' => user_message },
        { 'type' => 'image_url', 'image_url' => { 'url' => "data:image/png;base64,#{image_base64}", 'detail' => Config.image_detail } }
      ]
      messages << { 'role' => 'user', 'content' => user_content }

      body = {
        'model'       => Config.model,
        'messages'    => messages,
        'max_tokens'  => Config.get('max_tokens').to_i,
        'temperature' => Config.get('temperature').to_f,
        'stream'      => false
      }

      begin
        response = send_request(Config.api_url, api_key, body)
        return response if response['error']

        content = extract_content(response)
        @conversation_history << { 'role' => 'user', 'content' => "[截图] #{user_message}" }
        @conversation_history << { 'role' => 'assistant', 'content' => content }

        { 'error' => false, 'content' => content }
      rescue StandardError => e
        { 'error' => true, 'message' => "API请求失败: #{e.message}" }
      end
    end

    private

    def self.send_request(api_url, api_key, body)
      return send_responses_request(api_url, api_key, body) if Config.responses_api?

      send_chat_completions_request(api_url, api_key, body)
    end

    def self.send_chat_completions_request(api_url, api_key, body)
      uri = URI.parse(api_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = 15
      http.read_timeout = 60

      request = Net::HTTP::Post.new(uri.request_uri)
      request['Content-Type'] = 'application/json'
      request['Authorization'] = "Bearer #{api_key}"
      request.body = JSON.generate(body)

      response = http.request(request)

      if response.code.to_i == 200
        JSON.parse(response.body)
      else
        { 'error' => true, 'message' => "HTTP #{response.code}: #{response.body}" }
      end
    rescue StandardError => e
      { 'error' => true, 'message' => e.message }
    end

    def self.send_responses_request(api_url, api_key, body)
      endpoint = Config.normalize_api_url(api_url, 'responses')
      uri = URI.parse(endpoint)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = 15
      http.read_timeout = 60

      request = Net::HTTP::Post.new(uri.request_uri)
      request['Content-Type'] = 'application/json'
      request['Authorization'] = "Bearer #{api_key}"
      request.body = JSON.generate(to_responses_body(body))

      response = http.request(request)

      if response.code.to_i == 200
        JSON.parse(response.body)
      else
        { 'error' => true, 'message' => "HTTP #{response.code}: #{response.body}" }
      end
    rescue StandardError => e
      { 'error' => true, 'message' => e.message }
    end

    def self.to_responses_body(chat_body)
      messages = chat_body['messages'] || []
      instructions = messages
        .select { |msg| msg['role'] == 'system' }
        .map { |msg| message_content_to_text(msg['content']) }
        .join("\n\n")

      input_parts = responses_input_parts(messages.reject { |msg| msg['role'] == 'system' })

      body = {
        'model'             => chat_body['model'],
        'input'             => [{ 'role' => 'user', 'content' => input_parts }],
        'max_output_tokens' => chat_body['max_tokens'],
        'temperature'       => chat_body['temperature'],
        'stream'            => false
      }
      body['instructions'] = instructions unless instructions.empty?

      provider_config = Config.provider_config
      if provider_config['disable_response_storage']
        body['store'] = false
      end

      reasoning_effort = provider_config['reasoning_effort'].to_s
      unless reasoning_effort.empty?
        body['reasoning'] = { 'effort' => reasoning_effort }
      end

      body
    end

    def self.responses_input_parts(messages)
      transcript_chunks = []
      image_parts = []

      messages.each do |msg|
        role = (msg['role'] || 'user').to_s.upcase
        content = msg['content']

        if content.is_a?(Array)
          text_chunks = []
          content.each do |part|
            case part['type']
            when 'text'
              text_chunks << part['text'].to_s
            when 'image_url'
              image_url = part.dig('image_url', 'url').to_s
              next if image_url.empty?

              image_parts << {
                'type'      => 'input_image',
                'image_url' => image_url,
                'detail'    => (part.dig('image_url', 'detail') || Config.image_detail)
              }
            else
              text_chunks << part.to_s
            end
          end
          transcript_chunks << "#{role}:\n#{text_chunks.join("\n")}" unless text_chunks.empty?
        else
          transcript_chunks << "#{role}:\n#{content}"
        end
      end

      transcript = transcript_chunks.join("\n\n").strip
      input_parts = []
      input_parts << { 'type' => 'input_text', 'text' => transcript } unless transcript.empty?
      input_parts.concat(image_parts)
      input_parts << { 'type' => 'input_text', 'text' => '请根据当前上下文继续。' } if input_parts.empty?
      input_parts
    end

    def self.message_content_to_text(content)
      return content.to_s if content.is_a?(String)

      if content.is_a?(Array)
        return content.map do |part|
          case part['type']
          when 'text'
            part['text'].to_s
          when 'image_url'
            '[图片输入已附加。若当前中转站不支持视觉输入，请要求用户用文字描述图片关键内容。]'
          else
            part.to_s
          end
        end.join("\n")
      end

      content.to_s
    end

    def self.extract_content(response)
      chat_content = response.dig('choices', 0, 'message', 'content')
      return chat_content if chat_content && !chat_content.empty?

      output_text = response['output_text']
      return output_text if output_text && !output_text.empty?

      output = response['output']
      if output.is_a?(Array)
        texts = []
        output.each do |item|
          content = item['content']
          if content.is_a?(Array)
            content.each do |part|
              text = part['text'] || part['output_text']
              texts << text if text && !text.empty?
            end
          elsif content.is_a?(String)
            texts << content
          end
        end
        return texts.join("\n") unless texts.empty?
      end

      response['content'].to_s
    end
  end

  # ━━━━━━━━━━━━━━━━ 代码执行引擎 ━━━━━━━━━━━━━━━━
  module CodeExecutor
    def self.execute_code(code_str)
      model = Sketchup.active_model
      return { 'error' => true, 'message' => 'SketchUp 模型未打开' } unless model

      # 安全检查：禁止危险操作
      dangerous_patterns = [
        /require\s+['"]/,
        /eval\s*\(/,
        /system\s*\(/,
        /`.*`/,
        /File\s*\./,
        /Dir\s*\./,
        /IO\s*\./,
        /Kernel\s*\./,
        /spawn/,
        /fork/,
        /exec/
      ]

      dangerous_patterns.each do |pattern|
        return { 'error' => true, 'message' => '代码包含禁止的操作' } if code_str.match?(pattern)
      end

      begin
        entities = model.active_entities
        before_entities = entities.to_a

        # 在SketchUp的Ruby环境中执行代码
        Sketchup.send_action('ruby_console:toggle') rescue nil

        # 使用 model 的 API 执行
        eval_result = eval(code_str, binding)
        group_message = group_new_entities(model, entities, before_entities)
        message = group_message ? "代码执行成功，#{group_message}" : '代码执行成功'
        { 'error' => false, 'message' => message, 'result' => eval_result.to_s }
      rescue StandardError => e
        { 'error' => true, 'message' => "执行错误: #{e.message}" }
      end
    end

    def self.model_context
      model = Sketchup.active_model
      return 'SketchUp 模型未打开。' unless model

      entities = model.active_entities
      counts = Hash.new(0)
      names = []
      collect_entity_summary(entities, counts, names, 0)

      bounds = model.bounds rescue nil
      size_text = ''
      if bounds && bounds.valid?
        size_text = format(
          "模型包围盒约 %.2fm x %.2fm x %.2fm",
          bounds.width.to_f / 1.m,
          bounds.depth.to_f / 1.m,
          bounds.height.to_f / 1.m
        )
      end

      selection_count = model.selection.length rescue 0
      summary = []
      summary << size_text unless size_text.empty?
      summary << "当前选择数量：#{selection_count}"
      summary << "实体统计：#{counts.sort.map { |k, v| "#{k}=#{v}" }.join(', ')}"
      summary << "主要对象：#{names.first(12).join('、')}" unless names.empty?
      summary.join("\n")
    rescue StandardError => e
      "无法读取当前模型结构：#{e.message}"
    end

    def self.collect_entity_summary(entities, counts, names, depth)
      return if depth > 2

      entities.each do |entity|
        type_name = entity.typename rescue entity.class.name
        counts[type_name] += 1

        if grouped_entity?(entity)
          entity_name = entity.name.to_s rescue ''
          names << entity_name unless entity_name.empty?
          collect_entity_summary(entity.entities, counts, names, depth + 1) if entity.respond_to?(:entities)
        elsif entity.respond_to?(:definition)
          def_name = entity.definition.name.to_s rescue ''
          names << def_name unless def_name.empty?
        end
      end
    end

    def self.group_new_entities(model, entities, before_entities)
      before_ids = before_entities.map { |entity| entity.persistent_id rescue entity.object_id }
      new_entities = entities.to_a.select do |entity|
        entity.valid? && !before_ids.include?((entity.persistent_id rescue entity.object_id))
      end

      return nil if new_entities.empty?

      target = nil
      if new_entities.length == 1 && grouped_entity?(new_entities.first)
        target = new_entities.first
      else
        model.start_operation('整理AI生成对象', true)
        target = entities.add_group(new_entities)
        target.name = 'AI生成模型'
        model.commit_operation
      end

      model.selection.clear
      model.selection.add(target)
      model.active_view.zoom_extents
      "已将本次新增对象整理为一个整体：#{target.name.empty? ? target.typename : target.name}"
    rescue StandardError => e
      model.abort_operation rescue nil
      "但自动整理对象失败：#{e.message}"
    end

    def self.grouped_entity?(entity)
      entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
    end
  end

  # ━━━━━━━━━━━━━━━━ UI管理器 ━━━━━━━━━━━━━━━━
  class DialogManager
    def initialize
      @dialog = nil
    end

    def show
      if @dialog
        @dialog.bring_to_front
        return
      end

      @dialog = UI::HtmlDialog.new(
        title: 'AI建模助手 - AI+SU',
        preferences_key: 'AiSuModelingAssistant',
        width: 1200,
        height: 900,
        min_width: 800,
        min_height: 600
      )

      html_content = generate_html
      @dialog.set_html(html_content)

      setup_callbacks

      @dialog.show
    end

    private

    def generate_html
      <<~HTML
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>AI建模助手</title>
          <style>
            * {
              margin: 0;
              padding: 0;
              box-sizing: border-box;
            }

            body {
              font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
              background: #1a2332;
              color: #e0e0e0;
              height: 100vh;
              display: flex;
              flex-direction: column;
              overflow: hidden;
            }

            /* 标签栏 */
            .tab-bar {
              display: flex;
              background: #0f1419;
              border-bottom: 1px solid #2a3f5f;
              padding: 0;
              margin: 0;
              height: 45px;
            }

            .tab-btn {
              flex: 0 0 auto;
              padding: 0 20px;
              height: 45px;
              line-height: 45px;
              background: transparent;
              color: #888;
              border: none;
              cursor: pointer;
              font-size: 14px;
              border-bottom: 3px solid transparent;
              transition: all 0.2s;
            }

            .tab-btn:hover {
              color: #aaa;
              background: rgba(255,255,255,0.05);
            }

            .tab-btn.active {
              color: #60b3ff;
              border-bottom-color: #60b3ff;
            }

            /* 标签页容器 */
            .tab-content {
              display: none;
              flex: 1;
              overflow: hidden;
              flex-direction: column;
            }

            .tab-content.active {
              display: flex;
            }

            /* 对话标签页 */
            .chat-container {
              display: flex;
              flex-direction: column;
              height: 100%;
              position: relative;
            }

            /* 上部分 - 聊天区 */
            .chat-area {
              flex: 1;
              overflow-y: auto;
              padding: 15px;
              background: #1a2332;
              border-bottom: 1px solid #2a3f5f;
            }

            .message {
              margin-bottom: 15px;
              display: flex;
              gap: 10px;
            }

            .message.user {
              flex-direction: row-reverse;
            }

            .message-bubble {
              max-width: 70%;
              padding: 10px 15px;
              border-radius: 8px;
              word-wrap: break-word;
              line-height: 1.5;
              font-size: 13px;
            }

            .message.assistant .message-bubble {
              background: #2a3f5f;
              color: #e0e0e0;
            }

            .message.user .message-bubble {
              background: #0066cc;
              color: #fff;
            }

            .message-image {
              max-width: 100%;
              max-height: 300px;
              border-radius: 8px;
              margin-top: 10px;
            }

            .reference-strip {
              display: none;
              gap: 8px;
              flex-wrap: wrap;
              margin: 0 0 8px 0;
            }

            .reference-strip.has-images {
              display: flex;
            }

            .reference-chip {
              display: flex;
              align-items: center;
              gap: 6px;
              max-width: 220px;
              padding: 4px 8px 4px 4px;
              background: #132845;
              border: 1px solid #24517c;
              border-radius: 6px;
              color: #cfe7ff;
              font-size: 12px;
            }

            .reference-chip img {
              width: 34px;
              height: 34px;
              object-fit: cover;
              border-radius: 4px;
              flex: 0 0 auto;
            }

            .reference-chip button {
              border: 0;
              background: transparent;
              color: #9dc9f5;
              cursor: pointer;
              font-size: 14px;
              line-height: 1;
            }

            /* 代码块 */
            .code-block {
              background: #0f1419;
              border: 1px solid #2a3f5f;
              border-radius: 4px;
              padding: 10px;
              margin: 5px 0;
              font-family: 'Courier New', monospace;
              font-size: 12px;
              overflow-x: auto;
              color: #60b3ff;
            }

            /* 分割线 */
            .divider {
              width: 100%;
              height: 4px;
              background: #2a3f5f;
              cursor: row-resize;
              user-select: none;
            }

            /* 下部分 - Ruby控制台 */
            .console-area {
              flex: 0 0 35%;
              display: flex;
              flex-direction: column;
              background: #0f1419;
              border-top: 1px solid #2a3f5f;
            }

            .console-header {
              display: flex;
              justify-content: space-between;
              align-items: center;
              padding: 10px 15px;
              background: #151d2a;
              border-bottom: 1px solid #2a3f5f;
              height: 40px;
            }

            .console-title {
              font-weight: bold;
              font-size: 13px;
              color: #60b3ff;
            }

            .console-buttons {
              display: flex;
              gap: 8px;
            }

            .btn {
              padding: 6px 12px;
              border: 1px solid #2a3f5f;
              background: #1a2332;
              color: #60b3ff;
              border-radius: 4px;
              cursor: pointer;
              font-size: 12px;
              transition: all 0.2s;
            }

            .btn:hover {
              background: #2a3f5f;
              border-color: #3a5f7f;
            }

            .btn.primary {
              background: #0066cc;
              border-color: #0066cc;
              color: #fff;
            }

            .btn.primary:hover {
              background: #0052a3;
              border-color: #0052a3;
            }

            .console-content {
              flex: 1;
              overflow-y: auto;
              padding: 15px;
              font-family: 'Courier New', monospace;
              font-size: 12px;
              color: #60b3ff;
              white-space: pre-wrap;
              word-break: break-all;
              background: #0f1419;
              border: 1px solid #2a3f5f;
              margin: 10px;
              border-radius: 4px;
              outline: none;
              line-height: 1.4;
            }

            .console-content:focus {
              border-color: #60b3ff;
            }

            /* 输入区 */
            .input-area {
              padding: 10px 15px;
              background: #151d2a;
              border-top: 1px solid #2a3f5f;
              display: flex;
              gap: 8px;
            }

            .quick-buttons {
              display: flex;
              gap: 6px;
              margin-bottom: 8px;
            }

            .quick-btn {
              padding: 5px 10px;
              background: #1a2332;
              border: 1px solid #2a3f5f;
              color: #888;
              border-radius: 4px;
              cursor: pointer;
              font-size: 11px;
              transition: all 0.2s;
            }

            .quick-btn:hover {
              background: #2a3f5f;
              color: #aaa;
            }

            .input-row {
              display: flex;
              gap: 8px;
              align-items: flex-end;
            }

            input[type="text"] {
              flex: 1;
              padding: 8px 12px;
              background: #1a2332;
              border: 1px solid #2a3f5f;
              color: #e0e0e0;
              border-radius: 4px;
              font-size: 13px;
              outline: none;
            }

            input[type="text"]:focus {
              border-color: #60b3ff;
              background: #1a2f42;
            }

            /* 设置页面 */
            .settings-container {
              padding: 20px;
              overflow-y: auto;
              background: #1a2332;
            }

            .settings-group {
              margin-bottom: 25px;
              padding: 15px;
              background: #151d2a;
              border: 1px solid #2a3f5f;
              border-radius: 6px;
            }

            .settings-group-title {
              font-weight: bold;
              color: #60b3ff;
              margin-bottom: 12px;
              font-size: 13px;
              text-transform: uppercase;
            }

            .settings-row {
              margin-bottom: 12px;
            }

            .settings-label {
              display: block;
              margin-bottom: 6px;
              font-size: 12px;
              color: #aaa;
            }

            select, input[type="text"], input[type="password"], input[type="number"], textarea {
              width: 100%;
              padding: 8px 10px;
              background: #1a2332;
              border: 1px solid #2a3f5f;
              color: #e0e0e0;
              border-radius: 4px;
              font-size: 12px;
              outline: none;
              font-family: inherit;
            }

            select:focus, input[type="text"]:focus, input[type="password"]:focus, input[type="number"]:focus, textarea:focus {
              border-color: #60b3ff;
              background: #1a2f42;
            }

            .slider-row {
              display: flex;
              gap: 10px;
              align-items: center;
            }

            input[type="range"] {
              flex: 1;
            }

            .slider-value {
              min-width: 40px;
              text-align: right;
              font-size: 12px;
              color: #60b3ff;
            }

            .settings-button-group {
              display: flex;
              gap: 8px;
              margin-top: 15px;
            }

            .verify-btn {
              flex: 1;
              padding: 10px;
              background: #0066cc;
              border: 1px solid #0066cc;
              color: #fff;
              border-radius: 4px;
              cursor: pointer;
              font-size: 13px;
              font-weight: bold;
              transition: all 0.2s;
            }

            .verify-btn:hover {
              background: #0052a3;
              border-color: #0052a3;
            }

            .verify-status {
              margin-top: 8px;
              padding: 8px;
              border-radius: 4px;
              font-size: 12px;
              display: none;
            }

            .verify-status.success {
              background: rgba(0, 200, 0, 0.1);
              color: #00c800;
              display: block;
            }

            .verify-status.error {
              background: rgba(255, 0, 0, 0.1);
              color: #ff4444;
              display: block;
            }

            /* 关于页面 */
            .about-container {
              padding: 30px;
              overflow-y: auto;
              background: #1a2332;
            }

            .about-title {
              font-size: 24px;
              font-weight: bold;
              color: #60b3ff;
              margin-bottom: 10px;
            }

            .about-version {
              color: #888;
              margin-bottom: 20px;
              font-size: 13px;
            }

            .about-section {
              margin-bottom: 20px;
            }

            .about-section-title {
              font-weight: bold;
              color: #aaa;
              margin-bottom: 10px;
              font-size: 13px;
            }

            .about-text {
              color: #bbb;
              line-height: 1.6;
              font-size: 13px;
            }

            .about-link {
              color: #60b3ff;
              text-decoration: none;
            }

            .about-link:hover {
              text-decoration: underline;
            }

            /* 加载状态 */
            .loading {
              display: inline-block;
              color: #60b3ff;
            }

            .loading::after {
              content: '';
              animation: dots 1.5s steps(4, end) infinite;
            }

            @keyframes dots {
              0%, 20% { content: ''; }
              40% { content: '.'; }
              60% { content: '..'; }
              80%, 100% { content: '...'; }
            }

            /* 响应式 */
            @media (max-height: 600px) {
              .console-area {
                flex: 0 0 40%;
              }
            }
          </style>
        </head>
        <body>
          <!-- 标签栏 -->
          <div class="tab-bar">
            <button class="tab-btn active" data-tab="chat">对话</button>
            <button class="tab-btn" data-tab="settings">设置</button>
            <button class="tab-btn" data-tab="about">关于</button>
          </div>

          <!-- 对话页面 -->
          <div class="tab-content active" id="chat-tab">
            <div class="chat-container">
              <!-- 聊天区 -->
              <div class="chat-area" id="chatArea"></div>

              <!-- 分割线 -->
              <div class="divider" id="divider"></div>

              <!-- Ruby控制台 -->
              <div class="console-area">
                <div class="console-header">
                  <div class="console-title">▸ Ruby 控制台</div>
                  <div class="console-buttons">
                    <button class="btn" id="clearConsoleBtn">清空</button>
                    <button class="btn primary" id="executeBtn">▶ 执行</button>
                  </div>
                </div>
                <div id="consoleContent" class="console-content" contenteditable="true" spellcheck="false"></div>
              </div>

              <!-- 输入区 -->
              <div class="input-area">
                <div style="width: 100%;">
                  <div class="quick-buttons">
                    <button class="quick-btn" id="effectBtn" title="生成效果图">效果图</button>
                    <button class="quick-btn" id="attachImageBtn" title="上传参考图">参考图</button>
                    <button class="quick-btn" id="imageModelBtn" title="按参考图生成模型">按图建模</button>
                    <button class="quick-btn" id="codeBtn" title="生成建模代码">建模</button>
                    <button class="quick-btn" id="screenshotBtn" title="截图分析">截图分析</button>
                    <button class="quick-btn" id="screenshotFixBtn" title="根据当前截图修改模型">截图修正</button>
                    <button class="quick-btn" id="undoBtn" title="撤销">撤销</button>
                  </div>
                  <input type="file" id="referenceFileInput" accept="image/*" multiple style="display: none;" />
                  <div id="referenceStrip" class="reference-strip"></div>
                  <div class="input-row">
                    <input type="text" id="messageInput" placeholder="输入需求，或直接 Ctrl+V 粘贴效果图/截图..." />
                    <button class="btn primary" id="sendBtn">发送</button>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- 设置页面 -->
          <div class="tab-content" id="settings-tab">
            <div class="settings-container">
              <!-- API 连接设置 -->
              <div class="settings-group">
                <div class="settings-group-title">API 连接设置</div>

                <div class="settings-row">
                  <label class="settings-label">服务商</label>
                  <select id="providerSelect">
                    <option value="qwen">通义千问(百炼)</option>
                    <option value="kimi">Kimi(月之暗面)</option>
                    <option value="gemini">Google Gemini</option>
                    <option value="deepseek">DeepSeek</option>
                    <option value="xiaomi_tokenplan">小米 TokenPlan</option>
                    <option value="codex_cli_relay">Codex CLI 中转站</option>
                    <option value="custom">自定义(OpenAI兼容)</option>
                  </select>
                </div>

                <div class="settings-row">
                  <label class="settings-label">API URL</label>
                  <input type="text" id="apiUrlInput" placeholder="https://api.example.com/v1/chat/completions" />
                </div>

                <div class="settings-row">
                  <label class="settings-label">API Key</label>
                  <input type="password" id="apiKeyInput" placeholder="输入你的 API Key" />
                </div>

                <div class="settings-button-group">
                  <button class="verify-btn" id="verifyBtn">验证连接 & 获取模型</button>
                </div>
                <div class="verify-status" id="verifyStatus"></div>
              </div>

              <!-- 模型选择 -->
              <div class="settings-group">
                <div class="settings-group-title">模型配置</div>

                <div class="settings-row">
                  <label class="settings-label">对话模型</label>
                  <select id="modelSelect">
                    <option value="">-- 请先验证连接 --</option>
                  </select>
                </div>

                <div class="settings-row">
                  <label class="settings-label">温度 (Temperature)</label>
                  <div class="slider-row">
                    <input type="range" id="temperatureSlider" min="0" max="2" step="0.1" value="0.3" />
                    <span class="slider-value" id="temperatureValue">0.3</span>
                  </div>
                </div>

                <div class="settings-row">
                  <label class="settings-label">最大 Token 数</label>
                  <input type="number" id="maxTokensInput" value="4096" min="100" max="32000" step="100" />
                </div>
              </div>

              <!-- 文生图设置 -->
              <div class="settings-group">
                <div class="settings-group-title">文生图设置</div>

                <div class="settings-row">
                  <label class="settings-label">文生图服务商</label>
                  <select id="imageProviderSelect">
                    <option value="qwen">通义万象</option>
                    <option value="custom">自定义</option>
                  </select>
                </div>

                <div class="settings-row">
                  <label class="settings-label">文生图 API URL</label>
                  <input type="text" id="imageApiUrlInput" placeholder="https://dashscope.aliyuncs.com/compatible-mode/v1/images/generations" />
                </div>

                <div class="settings-row">
                  <label class="settings-label">文生图 API Key (可选)</label>
                  <input type="password" id="imageApiKeyInput" placeholder="留空则使用对话 API Key" />
                </div>

                <div class="settings-row">
                  <label class="settings-label">文生图模型</label>
                  <select id="imageModelSelect">
                    <option value="wanx2.1-t2i-turbo">wanx2.1-t2i-turbo</option>
                    <option value="wanx-v1">wanx-v1</option>
                  </select>
                </div>
              </div>

              <!-- 保存按钮 -->
              <button class="verify-btn" id="saveSettingsBtn" style="width: 100%; margin-top: 20px;">保存设置</button>
            </div>
          </div>

          <!-- 关于页面 -->
          <div class="tab-content" id="about-tab">
            <div class="about-container">
              <div class="about-title">AI建模助手</div>
              <div class="about-version">版本 1.2.0</div>

              <div class="about-section">
                <div class="about-section-title">功能特性</div>
                <div class="about-text">
                  • 通过自然语言描述设计需求<br>
                  • 三阶段工作流：方案沟通 → 参数确认 → 代码生成<br>
                  • AI 文生图功能：生成概念效果图<br>
                  • 图像理解：粘贴效果图按图建模，或截图后修正当前模型<br>
                  • Ruby 代码实时编辑和执行<br>
                  • 支持多个 AI 服务商<br>
                </div>
              </div>

              <div class="about-section">
                <div class="about-section-title">支持的 AI 服务</div>
                <div class="about-text">
                  • 通义千问 (百炼)<br>
                  • Kimi (月之暗面)<br>
                  • Google Gemini<br>
                  • DeepSeek<br>
                  • 小米 TokenPlan<br>
                  • Codex CLI 中转站<br>
                  • 任何 OpenAI 兼容的 API<br>
                </div>
              </div>

              <div class="about-section">
                <div class="about-section-title">工作流程</div>
                <div class="about-text">
                  <strong>第一步：方案沟通</strong><br>
                  用自然语言描述你的设计需求。AI 会帮你讨论方案、确认意图。<br>
                  <br>
                  <strong>第二步：参数确认</strong><br>
                  AI 会列出关键尺寸参数，让你逐一确认或修改。<br>
                  <br>
                  <strong>第三步：代码生成</strong><br>
                  参数确认后，AI 生成 SketchUp Ruby 代码。你可以在下方控制台编辑、执行。<br>
                </div>
              </div>

              <div class="about-section">
                <div class="about-section-title">快捷按钮</div>
                <div class="about-text">
                  • <strong>效果图</strong>：生成概念效果图<br>
                  • <strong>参考图</strong>：上传图片，聊天框也可直接 Ctrl+V 粘贴<br>
                  • <strong>按图建模</strong>：根据粘贴或上传的效果图生成建模方案<br>
                  • <strong>建模</strong>：生成 SketchUp 建模代码<br>
                  • <strong>截图分析</strong>：分析 SketchUp 中的截图<br>
                  • <strong>截图修正</strong>：根据当前视图截图生成修正方案或 Ruby 代码<br>
                  • <strong>撤销</strong>：撤销上一步操作<br>
                </div>
              </div>

              <div class="about-section">
                <div class="about-section-title">使用建议</div>
                <div class="about-text">
                  1. 先在"设置"页面配置 API Key<br>
                  2. 点击"验证连接 & 获取模型"确认连接<br>
                  3. 在聊天区自然语言描述设计需求<br>
                  4. 跟随 AI 的指导，完成三阶段工作流<br>
                  5. 在 Ruby 控制台中编辑、执行生成的代码<br>
                </div>
              </div>
            </div>
          </div>

          <script>
            // ========== 配置 ==========
            const PROVIDERS = {
              'qwen': {
                'name': '通义千问(百炼)',
                'chat_url': 'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
                'models_url': 'https://dashscope.aliyuncs.com/compatible-mode/v1/models',
                'api_mode': 'chat_completions',
                'image_url': 'https://dashscope.aliyuncs.com/compatible-mode/v1/images/generations',
                'default_model': 'qwen-coder-plus-latest'
              },
              'kimi': {
                'name': 'Kimi(月之暗面)',
                'chat_url': 'https://api.moonshot.cn/v1/chat/completions',
                'models_url': 'https://api.moonshot.cn/v1/models',
                'api_mode': 'chat_completions',
                'image_url': '',
                'default_model': 'moonshot-v1-128k'
              },
              'gemini': {
                'name': 'Google Gemini',
                'chat_url': 'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
                'models_url': 'https://generativelanguage.googleapis.com/v1beta/openai/models',
                'api_mode': 'chat_completions',
                'image_url': '',
                'default_model': 'gemini-2.0-flash'
              },
              'deepseek': {
                'name': 'DeepSeek',
                'chat_url': 'https://api.deepseek.com/v1/chat/completions',
                'models_url': 'https://api.deepseek.com/v1/models',
                'api_mode': 'chat_completions',
                'image_url': '',
                'default_model': 'deepseek-chat'
              },
              'xiaomi_tokenplan': {
                'name': '小米 TokenPlan',
                'chat_url': 'https://token-plan-cn.xiaomimimo.com/v1/chat/completions',
                'models_url': 'https://token-plan-cn.xiaomimimo.com/v1/models',
                'api_mode': 'chat_completions',
                'image_detail': 'high',
                'image_url': '',
                'default_model': 'mimo-v2.5-pro',
                'fallback_models': ['mimo-v2.5-pro', 'mimo-v2.5', 'mimo-v2-pro', 'mimo-v2-omni']
              },
              'codex_cli_relay': {
                'name': 'Codex CLI 中转站',
                'chat_url': 'https://www.hd1100.cc',
                'models_url': '',
                'api_mode': 'responses',
                'image_detail': 'high',
                'image_url': '',
                'default_model': 'gpt-5.4',
                'fallback_models': ['gpt-5.4', 'gpt-5.5', 'gpt-5'],
                'reasoning_effort': 'high',
                'disable_response_storage': true
              },
              'custom': {
                'name': '自定义(OpenAI兼容)',
                'chat_url': '',
                'models_url': '',
                'api_mode': 'chat_completions',
                'image_url': '',
                'default_model': ''
              }
            };

            // ========== 全局状态 ==========
            let state = {
              currentTab: 'chat',
              isLoading: false,
              referenceImages: [],
              pendingModel: ''
            };

            function callSketchup(callbackName, ...args) {
              if (window.sketchup && typeof window.sketchup[callbackName] === 'function') {
                window.sketchup[callbackName](...args);
                return true;
              }
              console.warn('SketchUp 回调不可用:', callbackName);
              return false;
            }

            // ========== 初始化 ==========
            window.addEventListener('DOMContentLoaded', function() {
              initializeEventListeners();
              loadSettings();
              loadConsoleContent();
            });

            function initializeEventListeners() {
              // 标签页切换
              document.querySelectorAll('.tab-btn').forEach(btn => {
                btn.addEventListener('click', function() {
                  switchTab(this.dataset.tab);
                });
              });

              // 聊天区
              document.getElementById('sendBtn').addEventListener('click', sendMessage);
              document.getElementById('messageInput').addEventListener('keypress', function(e) {
                if (e.key === 'Enter' && !e.shiftKey) {
                  e.preventDefault();
                  sendMessage();
                }
              });
              document.getElementById('messageInput').addEventListener('paste', handleReferencePaste);
              document.getElementById('referenceFileInput').addEventListener('change', handleReferenceFiles);

              // 快捷按钮
              document.getElementById('effectBtn').addEventListener('click', generateEffect);
              document.getElementById('attachImageBtn').addEventListener('click', function() {
                document.getElementById('referenceFileInput').click();
              });
              document.getElementById('imageModelBtn').addEventListener('click', generateModelFromReference);
              document.getElementById('codeBtn').addEventListener('click', generateCode);
              document.getElementById('screenshotBtn').addEventListener('click', analyzeScreenshot);
              document.getElementById('screenshotFixBtn').addEventListener('click', reviseFromScreenshot);
              document.getElementById('undoBtn').addEventListener('click', undo);

              // Ruby 控制台
              document.getElementById('executeBtn').addEventListener('click', executeCode);
              document.getElementById('clearConsoleBtn').addEventListener('click', clearConsole);

              // 设置页面
              document.getElementById('providerSelect').addEventListener('change', onProviderChange);
              document.getElementById('verifyBtn').addEventListener('click', verifyConnection);
              document.getElementById('saveSettingsBtn').addEventListener('click', saveSettings);
              document.getElementById('temperatureSlider').addEventListener('input', function() {
                document.getElementById('temperatureValue').textContent = this.value;
              });

              // 分割线拖动
              initDividerResize();

              // 自动保存控制台内容
              document.getElementById('consoleContent').addEventListener('input', function() {
                try {
                  callSketchup('save_console', this.textContent || '');
                } catch(e) {
                  console.log('保存控制台失败:', e);
                }
              });
            }

            function switchTab(tabName) {
              // 更新按钮
              document.querySelectorAll('.tab-btn').forEach(btn => {
                btn.classList.remove('active');
              });
              document.querySelector(`[data-tab="${tabName}"]`).classList.add('active');

              // 更新内容
              document.querySelectorAll('.tab-content').forEach(tab => {
                tab.classList.remove('active');
              });
              document.getElementById(`${tabName}-tab`).classList.add('active');

              state.currentTab = tabName;
            }

            function initDividerResize() {
              const divider = document.getElementById('divider');
              const chatArea = document.querySelector('.chat-area');
              const consoleArea = document.querySelector('.console-area');
              let isResizing = false;
              let startY = 0;
              let startChatHeight = 0;

              divider.addEventListener('mousedown', function(e) {
                isResizing = true;
                startY = e.clientY;
                startChatHeight = chatArea.offsetHeight;
                document.body.style.cursor = 'row-resize';
                document.body.style.userSelect = 'none';
              });

              document.addEventListener('mousemove', function(e) {
                if (!isResizing) return;

                const container = document.querySelector('.chat-container');
                const delta = e.clientY - startY;
                const newChatHeight = Math.max(200, startChatHeight + delta);
                const newConsoleHeight = container.offsetHeight - newChatHeight - 4; // 4 = divider height

                if (newConsoleHeight >= 150) {
                  chatArea.style.flex = '0 0 ' + newChatHeight + 'px';
                  consoleArea.style.flex = '0 0 ' + newConsoleHeight + 'px';
                }
              });

              document.addEventListener('mouseup', function() {
                isResizing = false;
                document.body.style.cursor = 'auto';
                document.body.style.userSelect = 'auto';
              });
            }

            // ========== 聊天功能 ==========
            function sendMessage() {
              const input = document.getElementById('messageInput');
              const message = input.value.trim();

              if (!message && state.referenceImages.length === 0) return;

              // 显示用户消息
              const displayMessage = state.referenceImages.length > 0
                ? message + '\\n[参考图 ' + state.referenceImages.length + ' 张]'
                : message;
              addMessage('user', displayMessage);
              input.value = '';
              input.placeholder = '输入需求，或直接 Ctrl+V 粘贴效果图/截图...';

              // 调用 Ruby 发送消息
              state.isLoading = true;
              if (state.referenceImages.length > 0) {
                const payload = JSON.stringify(state.referenceImages);
                state.referenceImages = [];
                renderReferenceStrip();
                callSketchup('send_message_with_refs', message || '请根据参考图先沟通建模细节。', payload);
              } else {
                callSketchup('send_message', message);
              }
            }

            function handleReferencePaste(event) {
              const items = event.clipboardData && event.clipboardData.items;
              if (!items) return;

              for (let i = 0; i < items.length; i++) {
                const item = items[i];
                if (item.kind === 'file' && item.type.indexOf('image/') === 0) {
                  event.preventDefault();
                  const file = item.getAsFile();
                  addReferenceImage(file);
                }
              }
            }

            function handleReferenceFiles(event) {
              const files = Array.from(event.target.files || []);
              files.forEach(file => addReferenceImage(file));
              event.target.value = '';
            }

            function addReferenceImage(file) {
              if (!file) return;
              if (!file.type || file.type.indexOf('image/') !== 0) {
                alert('请选择图片文件');
                return;
              }
              if (state.referenceImages.length >= 3) {
                alert('一次最多粘贴 3 张参考图');
                return;
              }

              const reader = new FileReader();
              reader.onload = function() {
                state.referenceImages.push({
                  name: file.name || 'clipboard-image',
                  mime: file.type || 'image/png',
                  data_url: reader.result
                });
                renderReferenceStrip();
                showDraftHint();
              };
              resizeImageFile(file, function(dataUrl) {
                if (dataUrl) {
                  state.referenceImages.push({
                    name: file.name || 'clipboard-image',
                    mime: 'image/jpeg',
                    data_url: dataUrl
                  });
                  renderReferenceStrip();
                  showDraftHint();
                } else {
                  reader.readAsDataURL(file);
                }
              });
            }

            function resizeImageFile(file, callback) {
              const reader = new FileReader();
              reader.onload = function() {
                const img = new Image();
                img.onload = function() {
                  const maxSize = 1600;
                  const scale = Math.min(1, maxSize / Math.max(img.width, img.height));
                  const width = Math.max(1, Math.round(img.width * scale));
                  const height = Math.max(1, Math.round(img.height * scale));
                  const canvas = document.createElement('canvas');
                  canvas.width = width;
                  canvas.height = height;
                  const ctx = canvas.getContext('2d');
                  ctx.drawImage(img, 0, 0, width, height);
                  callback(canvas.toDataURL('image/jpeg', 0.86));
                };
                img.onerror = function() { callback(null); };
                img.src = reader.result;
              };
              reader.onerror = function() { callback(null); };
              reader.readAsDataURL(file);
            }

            function renderReferenceStrip() {
              const strip = document.getElementById('referenceStrip');
              strip.innerHTML = '';
              strip.classList.toggle('has-images', state.referenceImages.length > 0);
              if (state.referenceImages.length === 0) {
                document.getElementById('messageInput').placeholder = '输入需求，或直接 Ctrl+V 粘贴效果图/截图...';
              }

              state.referenceImages.forEach((ref, index) => {
                const chip = document.createElement('div');
                chip.className = 'reference-chip';
                chip.innerHTML =
                  '<img src="' + ref.data_url + '" alt="参考图">' +
                  '<span>参考图 ' + (index + 1) + '</span>' +
                  '<button title="移除" data-index="' + index + '">×</button>';
                chip.querySelector('button').addEventListener('click', function() {
                  state.referenceImages.splice(parseInt(this.dataset.index, 10), 1);
                  renderReferenceStrip();
                });
                strip.appendChild(chip);
              });
            }

            function showDraftHint() {
              const input = document.getElementById('messageInput');
              if (!input.value.trim()) {
                input.placeholder = '已粘贴参考图：输入要求后发送，或点“按图建模”';
              }
              input.focus();
            }

            function addMessage(role, content) {
              const chatArea = document.getElementById('chatArea');
              const div = document.createElement('div');
              div.className = 'message ' + role;

              // 简单的 Markdown 处理
              let html = escapeHtml(content);

              // 代码块
              html = html.replace(/```ruby\\n([\\s\\S]*?)```/g, function(match, code) {
                return '<div class="code-block">' + escapeHtml(code.trim()) + '</div>';
              });

              // 链接
              html = html.replace(/\\[(.*?)\\]\\((.*?)\\)/g, '<a href="$2" target="_blank" style="color: #60b3ff; text-decoration: underline;">$1</a>');

              // 换行
              html = html.replace(/\\n/g, '<br>');

              const bubble = document.createElement('div');
              bubble.className = 'message-bubble';
              bubble.innerHTML = html;
              div.appendChild(bubble);

              chatArea.appendChild(div);
              chatArea.scrollTop = chatArea.scrollHeight;
            }

            function escapeHtml(text) {
              const div = document.createElement('div');
              div.textContent = text;
              return div.innerHTML;
            }

            function generateEffect() {
              const input = document.getElementById('messageInput');
              const message = input.value.trim();

              if (!message) {
                alert('请先输入设计描述');
                return;
              }

              addMessage('user', '生成效果图: ' + message);
              input.value = '';

              state.isLoading = true;
              callSketchup('generate_image', message);
            }

            function generateModelFromReference() {
              const input = document.getElementById('messageInput');
              const userNote = input.value.trim();

              if (state.referenceImages.length === 0) {
                alert('请先粘贴或上传参考图');
                return;
              }

              const prompt =
                '请根据我附上的效果图/参考图进行图像理解，并转成 SketchUp 可建模方案。' +
                '先识别主体造型、构件层级、比例关系、材质和需要保留的视觉特征；' +
                '如果缺少真实尺寸，请给出合理默认尺寸并让我确认。' +
                '如果我已经明确要求直接建模，请在列出关键假设后生成完整 SketchUp Ruby 代码。' +
                (userNote ? '\\n\\n用户补充：' + userNote : '');

              addMessage('user', '按参考图建模' + (userNote ? ': ' + userNote : '') + '\\n[参考图 ' + state.referenceImages.length + ' 张]');
              input.value = '';

              const payload = JSON.stringify(state.referenceImages);
              state.referenceImages = [];
              renderReferenceStrip();
              state.isLoading = true;
              callSketchup('send_message_with_refs', prompt, payload);
            }

            function generateCode() {
              const input = document.getElementById('messageInput');
              const message = input.value.trim();

              if (!message) {
                alert('请先输入建模要求');
                return;
              }

              addMessage('user', '生成建模代码: ' + message);
              input.value = '';

              state.isLoading = true;
              callSketchup('send_message', '请进入代码生成前的参数确认流程。用户需求：' + message);
            }

            function analyzeScreenshot() {
              const input = document.getElementById('messageInput');
              const note = input.value.trim();
              const prompt =
                '请分析这张 SketchUp 当前截图，描述当前模型状态、可见问题和继续优化建议。' +
                '除非我明确要求生成代码，否则先不要输出 Ruby 代码。' +
                (note ? '\\n\\n用户补充：' + note : '');
              addMessage('user', '正在分析截图' + (note ? ': ' + note : '') + '...');
              input.value = '';
              state.isLoading = true;
              callSketchup('analyze_screenshot', prompt);
            }

            function reviseFromScreenshot() {
              const input = document.getElementById('messageInput');
              const note = input.value.trim();
              const prompt =
                '请根据这张 SketchUp 当前截图和模型结构，找出当前模型需要修正的地方，' +
                '例如构件漂浮、门窗未贴墙、比例不协调、散件未组合、位置偏移等。' +
                '请优先生成用于修正现有模型的 SketchUp Ruby 代码，尽量保留已有对象，只修正必要几何和位置。' +
                (note ? '\\n\\n用户补充：' + note : '');
              addMessage('user', '根据当前截图修正模型' + (note ? ': ' + note : '') + '...');
              input.value = '';
              state.isLoading = true;
              callSketchup('analyze_screenshot', prompt);
            }

            function undo() {
              callSketchup('undo');
              addMessage('assistant', '已撤销上一步操作');
            }

            // ========== Ruby 控制台 ==========
            function executeCode() {
              const code = document.getElementById('consoleContent').textContent;

              if (!code.trim()) {
                alert('控制台为空，请先生成代码');
                return;
              }

              callSketchup('execute_code', code);
              addMessage('assistant', '正在执行 Ruby 代码...');
            }

            function clearConsole() {
              if (confirm('确定要清空 Ruby 控制台吗？')) {
                document.getElementById('consoleContent').textContent = '';
                callSketchup('save_console', '');
              }
            }

            function insertCodeToConsole(code) {
              const console = document.getElementById('consoleContent');

              // 提取代码块
              const match = code.match(/```ruby\\n([\\s\\S]*?)```/);
              let codeToInsert = match ? match[1].trim() : code;

              // 如果已有内容，换行添加
              if (console.textContent.trim()) {
                console.textContent += '\\n\\n' + codeToInsert;
              } else {
                console.textContent = codeToInsert;
              }

              console.scrollTop = console.scrollHeight;
              callSketchup('save_console', console.textContent);
            }

            // ========== 设置页面 ==========
            function loadSettings() {
              callSketchup('load_settings', '');
            }

            function onLoadSettings(data) {
              const settings = JSON.parse(data);

              document.getElementById('providerSelect').value = settings.provider || 'qwen';
              document.getElementById('apiUrlInput').value = settings.api_url || '';
              document.getElementById('apiKeyInput').value = settings.api_key || '';
              document.getElementById('modelSelect').value = settings.model || '';
              document.getElementById('temperatureSlider').value = settings.temperature || 0.3;
              document.getElementById('temperatureValue').textContent = settings.temperature || 0.3;
              document.getElementById('maxTokensInput').value = settings.max_tokens || 4096;

              document.getElementById('imageApiUrlInput').value = settings.image_api_url || '';
              document.getElementById('imageApiKeyInput').value = settings.image_api_key || '';
              document.getElementById('imageModelSelect').value = settings.image_model || 'wanx2.1-t2i-turbo';

              applyProviderDefaults(false, settings.model || '');
            }

            function onProviderChange() {
              applyProviderDefaults(true, '');
            }

            function updateProviderUrl() {
              applyProviderDefaults(false, document.getElementById('modelSelect').value);
            }

            function applyProviderDefaults(forceUrl, selectedModel) {
              const provider = document.getElementById('providerSelect').value;
              const providerConfig = PROVIDERS[provider];
              const apiUrlInput = document.getElementById('apiUrlInput');

              if (provider === 'custom') {
                if (forceUrl) apiUrlInput.value = '';
              } else if (forceUrl || !apiUrlInput.value.trim() || isStaleProviderDefaultUrl(apiUrlInput.value.trim(), provider)) {
                apiUrlInput.value = providerConfig.chat_url;
                if (providerConfig.image_url) {
                  document.getElementById('imageApiUrlInput').value = providerConfig.image_url;
                }
              }

              ensureModelOption(selectedModel || providerConfig.default_model || '');
            }

            function isStaleProviderDefaultUrl(apiUrl, provider) {
              if (!apiUrl || !PROVIDERS[provider]) return false;
              if (apiUrl === PROVIDERS[provider].chat_url) return false;
              return Object.keys(PROVIDERS).some(key => {
                const defaultUrl = PROVIDERS[key].chat_url || '';
                return defaultUrl && apiUrl === defaultUrl;
              });
            }

            function verifyConnection() {
              const provider = document.getElementById('providerSelect').value;
              const apiUrl = document.getElementById('apiUrlInput').value.trim();
              const apiKey = document.getElementById('apiKeyInput').value.trim();
              const status = document.getElementById('verifyStatus');

              if (!apiUrl || !apiKey) {
                showVerifyStatus('error', '请输入 API URL 和 API Key');
                return;
              }

              status.innerHTML = '<span class="loading">正在验证</span>';
              status.classList.remove('success', 'error');

              state.pendingModel = document.getElementById('modelSelect').value || (PROVIDERS[provider] && PROVIDERS[provider].default_model) || '';
              callSketchup('fetch_models', JSON.stringify({
                provider: provider,
                api_url: apiUrl,
                api_key: apiKey
              }));
            }

            function onModelsLoaded(modelsJson) {
              const models = JSON.parse(modelsJson);
              const modelSelect = document.getElementById('modelSelect');

              modelSelect.innerHTML = '';
              models.forEach(model => {
                const option = document.createElement('option');
                option.value = model;
                option.textContent = model;
                modelSelect.appendChild(option);
              });

              if (models.length > 0) {
                const provider = document.getElementById('providerSelect').value;
                const fallbackModel = (PROVIDERS[provider] && PROVIDERS[provider].default_model) || '';
                const preferredModel = state.pendingModel || fallbackModel;
                if (preferredModel && models.includes(preferredModel)) {
                  modelSelect.value = preferredModel;
                } else if (fallbackModel && models.includes(fallbackModel)) {
                  modelSelect.value = fallbackModel;
                } else {
                  modelSelect.value = models[0];
                }
              }

              showVerifyStatus('success', '连接成功！已获取 ' + models.length + ' 个模型');
            }

            function ensureModelOption(model) {
              const modelSelect = document.getElementById('modelSelect');
              if (!model) return;

              const exists = Array.from(modelSelect.options).some(option => option.value === model);
              if (!exists) {
                modelSelect.innerHTML = '';
                const option = document.createElement('option');
                option.value = model;
                option.textContent = model;
                modelSelect.appendChild(option);
              }
              modelSelect.value = model;
            }

            function onModelsFailed(error) {
              showVerifyStatus('error', '连接失败: ' + error);
            }

            function showVerifyStatus(type, message) {
              const status = document.getElementById('verifyStatus');
              status.className = 'verify-status ' + type;
              status.textContent = message;
            }

            function saveSettings() {
              const settings = {
                provider: document.getElementById('providerSelect').value,
                api_url: document.getElementById('apiUrlInput').value,
                api_key: document.getElementById('apiKeyInput').value,
                model: document.getElementById('modelSelect').value,
                temperature: parseFloat(document.getElementById('temperatureSlider').value),
                max_tokens: parseInt(document.getElementById('maxTokensInput').value),
                image_api_url: document.getElementById('imageApiUrlInput').value,
                image_api_key: document.getElementById('imageApiKeyInput').value,
                image_model: document.getElementById('imageModelSelect').value
              };

              callSketchup('save_settings', JSON.stringify(settings));
              alert('设置已保存');
            }

            function loadConsoleContent() {
              callSketchup('load_console', '');
            }

            function onLoadConsole(content) {
              document.getElementById('consoleContent').textContent = content || '';
            }

            // ========== Ruby 回调处理 ==========
            window.onLoadSettings = onLoadSettings;
            window.onLoadConsole = onLoadConsole;
            window.onModelsLoaded = onModelsLoaded;
            window.onModelsFailed = onModelsFailed;

            window.onChatMessage = function(content) {
              addMessage('assistant', content);
              // 只在内容包含ruby代码块时自动插入控制台
              if (content.match(/```ruby/)) {
                insertCodeToConsole(content);
              }
              state.isLoading = false;
            };

            window.onChatError = function(error) {
              addMessage('assistant', '错误: ' + error);
              state.isLoading = false;
            };

            window.onImageStart = function() {
              addMessage('assistant', '正在生成效果图，请稍候...');
            };

            window.onImageGenerated = function(imageData) {
              const chatArea = document.getElementById('chatArea');
              const div = document.createElement('div');
              div.className = 'message assistant';

              const bubble = document.createElement('div');
              bubble.className = 'message-bubble';

              const img = document.createElement('img');
              img.className = 'message-image';
              img.src = 'data:image/png;base64,' + imageData;

              bubble.appendChild(img);
              div.appendChild(bubble);
              chatArea.appendChild(div);
              chatArea.scrollTop = chatArea.scrollHeight;

              state.isLoading = false;
            };

            window.onImageUrl = function(url) {
              const chatArea = document.getElementById('chatArea');
              const div = document.createElement('div');
              div.className = 'message assistant';

              const bubble = document.createElement('div');
              bubble.className = 'message-bubble';
              bubble.innerHTML = '<p>效果图已生成:</p><img class="message-image" src="' + url + '" />';
              div.appendChild(bubble);
              chatArea.appendChild(div);
              chatArea.scrollTop = chatArea.scrollHeight;
              state.isLoading = false;
            };

            window.onImageError = function(error) {
              addMessage('assistant', '生成效果图失败: ' + error);
              state.isLoading = false;
            };

            window.onCodeExecuted = function(result) {
              addMessage('assistant', '代码执行成功: ' + result);
            };

            window.onCodeExecuteError = function(error) {
              addMessage('assistant', '代码执行失败: ' + error);
            };
          </script>
        </body>
        </html>
      HTML
    end

    def setup_callbacks
      # 聊天消息回调
      @dialog.add_action_callback('send_message') { |_ctx, user_message|
        Thread.new do
          begin
            response = ApiClient.chat(user_message)
            if response['error']
              js_err = response['message'].gsub("\\", "\\\\\\\\").gsub("'", "\\\\'").gsub("\n", "\\n").gsub("\r", "")
              @dialog.execute_script("onChatError('#{js_err}')")
            else
              content = response['content'].gsub("\\", "\\\\\\\\").gsub("'", "\\\\'").gsub("\n", "\\n").gsub("\r", "")
              @dialog.execute_script("onChatMessage('#{content}')")
            end
          rescue => e
            js_err = e.message.gsub("\\", "\\\\\\\\").gsub("'", "\\\\'").gsub("\n", "\\n").gsub("\r", "")
            @dialog.execute_script("onChatError('#{js_err}')")
          end
        end
      }

      # 带参考图的聊天消息回调
      @dialog.add_action_callback('send_message_with_refs') { |_ctx, user_message, references_json|
        Thread.new do
          begin
            response = ApiClient.chat_with_reference_images(user_message, references_json)
            if response['error']
              js_err = response['message'].gsub("\\", "\\\\\\\\").gsub("'", "\\\\'").gsub("\n", "\\n").gsub("\r", "")
              @dialog.execute_script("onChatError('#{js_err}')")
            else
              content = response['content'].gsub("\\", "\\\\\\\\").gsub("'", "\\\\'").gsub("\n", "\\n").gsub("\r", "")
              @dialog.execute_script("onChatMessage('#{content}')")
            end
          rescue => e
            js_err = e.message.gsub("\\", "\\\\\\\\").gsub("'", "\\\\'").gsub("\n", "\\n").gsub("\r", "")
            @dialog.execute_script("onChatError('#{js_err}')")
          end
        end
      }

      # 生成效果图回调
      @dialog.add_action_callback('generate_image') { |_ctx, prompt|
        Thread.new do
          begin
            @dialog.execute_script("onImageStart()")

            image_url = Config.image_api_url
            image_key = Config.image_api_key
            image_model = Config.image_model

            # 如果未单独设置，使用 API key
            image_key = Config.api_key if image_key.nil? || image_key.empty?

            result = ImageGen.generate(prompt, image_url, image_key, image_model)

            if result['error']
              @dialog.execute_script("onImageError('#{result['message'].gsub("'", "\\\\'")}')")
            elsif result['image_b64']
              # Base64 数据需要分段传输
              b64 = result['image_b64']
              # 截断显示消息
              display = b64[0..100]
              @dialog.execute_script("onImageGenerated('#{b64}')")
            elsif result['image_url']
              url = result['image_url'].gsub("'", "\\\\'")
              @dialog.execute_script("onImageUrl('#{url}')")
            end
          rescue => e
            @dialog.execute_script("onImageError('#{e.message.gsub("'", "\\\\'")}')")
          end
        end
      }

      # 截图分析回调
      @dialog.add_action_callback('analyze_screenshot') { |_ctx, user_prompt = nil|
        Thread.new do
          begin
            model = Sketchup.active_model
            view = model.active_view rescue nil
            unless view
              @dialog.execute_script("onChatError('请先打开一个SketchUp模型')")
              next
            end

            # 使用SketchUp内置截图功能
            temp_file = File.join(ENV['TEMP'] || '/tmp', "su_screenshot_#{Time.now.to_i}.png")
            view.write_image(temp_file, 1920, 1080, false, 1.0)

            if File.exist?(temp_file) && File.size(temp_file) > 0
              image_data = File.binread(temp_file)
              image_base64 = Base64.strict_encode64(image_data)
              File.delete(temp_file) rescue nil

              prompt = user_prompt.to_s.strip
              prompt = '请分析这张 SketchUp 截图，描述当前模型状态，并提出优化建议或继续建模的方案:' if prompt.empty?
              context = CodeExecutor.model_context rescue '无法读取当前模型结构。'
              response = ApiClient.chat_with_image("#{prompt}\n\n[当前SketchUp模型结构]\n#{context}", image_base64)

              if response['error']
                @dialog.execute_script("onChatError('#{response['message'].gsub("'", "\\\\'")}')")
              else
                content = response['content'].gsub("\\", "\\\\\\\\").gsub("'", "\\\\'").gsub("\n", "\\n").gsub("\r", "")
                @dialog.execute_script("onChatMessage('#{content}')")
              end
            else
              @dialog.execute_script("onChatError('截图失败，请确保有打开的模型视图')")
            end
          rescue => e
            @dialog.execute_script("onChatError('截图分析失败: #{e.message.gsub("'", "\\\\'")}')")
          end
        end
      }

      # 撤销回调 — 必须在主线程执行！
      @dialog.add_action_callback('undo') { |_ctx|
        begin
          Sketchup.active_model.abort_operation rescue nil
          Sketchup.send_action('editUndo:')
        rescue => e
          @dialog.execute_script("onChatError('撤销失败: #{e.message.gsub("'", "\\\\'")}')")
        end
      }

      # 执行 Ruby 代码 — 必须在主线程执行！
      @dialog.add_action_callback('execute_code') { |_ctx, code_str|
        begin
          result = CodeExecutor.execute_code(code_str)
          if result['error']
            @dialog.execute_script("onCodeExecuteError('#{result['message'].gsub("'", "\\\\'")}')")
          else
            @dialog.execute_script("onCodeExecuted('#{result['message']}')")
          end
        rescue => e
          @dialog.execute_script("onCodeExecuteError('#{e.message.gsub("'", "\\\\'")}')")
        end
      }

      # 获取模型列表
      @dialog.add_action_callback('fetch_models') { |_ctx, params|
        Thread.new do
          begin
            if params.to_s.strip.start_with?('{')
              payload = JSON.parse(params)
              provider = payload['provider']
              api_url = payload['api_url']
              api_key = payload['api_key']
            else
              provider = Config.provider
              api_url, api_key = params.split('|', 2)
            end
            result = ModelFetcher.fetch_models(api_url, api_key, provider)

            if result['error']
              @dialog.execute_script("onModelsFailed('#{result['message'].gsub("'", "\\\\'")}')")
            else
              models_json = JSON.generate(result['models'])
              @dialog.execute_script("onModelsLoaded('#{models_json.gsub("'", "\\\\'")}')")
            end
          rescue => e
            @dialog.execute_script("onModelsFailed('#{e.message.gsub("'", "\\\\'")}')")
          end
        end
      }

      # 保存设置
      @dialog.add_action_callback('save_settings') { |_ctx, json_str|
        Thread.new do
          begin
            settings = JSON.parse(json_str)
            Config.set_all(settings)
            @dialog.execute_script("alert('设置已保存')")
          rescue => e
            @dialog.execute_script("alert('保存设置失败: #{e.message.gsub("'", "\\\\'")}')")
          end
        end
      }

      # 加载设置
      @dialog.add_action_callback('load_settings') { |_ctx|
        Thread.new do
          begin
            settings = Config.get_all
            json_str = JSON.generate(settings).gsub("'", "\\\\'")
            @dialog.execute_script("onLoadSettings('#{json_str}')")
          rescue => e
            @dialog.execute_script("alert('加载设置失败: #{e.message.gsub("'", "\\\\'")}')")
          end
        end
      }

      # 保存控制台内容
      @dialog.add_action_callback('save_console') { |_ctx, content|
        Thread.new do
          begin
            Sketchup.write_default(PLUGIN_ID, 'console_content', content)
          rescue => e
            # 静默失败
          end
        end
      }

      # 加载控制台内容
      @dialog.add_action_callback('load_console') { |_ctx|
        Thread.new do
          begin
            content = Sketchup.read_default(PLUGIN_ID, 'console_content') || ''
            escaped = content.gsub("'", "\\\\'").gsub("\n", "\\n")
            @dialog.execute_script("onLoadConsole('#{escaped}')")
          rescue => e
            @dialog.execute_script("onLoadConsole('')")
          end
        end
      }
    end
  end

  # ━━━━━━━━━━━━━━━━ 菜单入口 ━━━━━━━━━━━━━━━━
  def self.show_dialog
    @dialog_manager ||= DialogManager.new
    @dialog_manager.show
  end

  # 添加菜单项
  unless file_loaded?(__FILE__)
    menu = UI.menu('Extensions').add_submenu(PLUGIN_NAME)
    menu.add_item('打开对话') { show_dialog }
    menu.add_item('清除历史记录') { ApiClient.clear_history }
    menu.add_separator
    menu.add_item('关于') { show_dialog }

    file_loaded(__FILE__)
  end
end
