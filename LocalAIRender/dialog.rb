# frozen_string_literal: true

require 'json'
require 'uri'
require 'base64'
require 'thread'

module LLGHD
  module LocalAIRender
    class Dialog
      WIDTH = 980
      HEIGHT = 680

      def initialize
        @dialog = UI::HtmlDialog.new(
          dialog_title: EXTENSION_NAME,
          preferences_key: EXTENSION_ID,
          scrollable: true,
          resizable: true,
          width: WIDTH,
          height: HEIGHT,
          style: UI::HtmlDialog::STYLE_DIALOG
        )
        @dialog.set_file(File.join(PLUGIN_DIR, 'ui.html'))
        register_callbacks
      end

      def show
        @dialog.show
        send_to_js('settings', settings_payload)
        send_to_js('history', LocalAIRender.load_history)
        send_to_js('inspiration_history', LocalAIRender.load_inspiration_history)
      rescue StandardError
        nil
      end

      private

      def register_callbacks
        @dialog.add_action_callback('ready') do |_context, _payload|
          send_to_js('settings', settings_payload)
          send_to_js('history', LocalAIRender.load_history)
          send_to_js('inspiration_history', LocalAIRender.load_inspiration_history)
        end

        @dialog.add_action_callback('capture_view') do |_context, payload|
          data = parse_payload(payload)
          send_to_js('capture_view', LocalAIRender.capture_view(width: data['width'], height: data['height']))
        end

        @dialog.add_action_callback('camera_snapshot') do |_context, _payload|
          send_to_js('camera_snapshot', { ok: true, camera: Camera.snapshot })
        end

        @dialog.add_action_callback('list_scene_views') do |_context, payload|
          data = parse_payload(payload)
          send_to_js(
            'list_scene_views',
            LocalAIRender.list_scene_views(
              width: data['width'],
              height: data['height'],
              offset: data['offset'],
              limit: data['limit']
            )
          )
        end

        @dialog.add_action_callback('capture_scene_view') do |_context, payload|
          data = parse_payload(payload)
          send_to_js(
            'capture_scene_view',
            LocalAIRender.capture_scene_view(
              page_index: data['page_index'],
              width: data['width'],
              height: data['height']
            )
          )
        end

        @dialog.add_action_callback('upload_image') do |_context, payload|
          data = parse_payload(payload)
          result = LocalAIRender.save_uploaded_data_url(data['data_url'], data['name'])
          send_to_js('upload_image', result)
        end

        @dialog.add_action_callback('save_settings') do |_context, payload|
          send_to_js('save_settings', LocalAIRender.save_settings(parse_payload(payload)))
        end

        @dialog.add_action_callback('test_api') do |_context, payload|
          send_to_js('test_api', LocalAIRender.test_api(parse_payload(payload)))
        end

        @dialog.add_action_callback('test_text_api') do |_context, payload|
          send_to_js('test_text_api', LocalAIRender.test_text_api(parse_payload(payload)))
        end

        @dialog.add_action_callback('apply_builtin_channel') do |_context, _payload|
          send_to_js('apply_builtin_channel', LocalAIRender.apply_builtin_channel)
        end

        @dialog.add_action_callback('update_plugin') do |_context, payload|
          send_to_js('update_plugin', LocalAIRender.update_plugin(parse_payload(payload)))
        end

        @dialog.add_action_callback('render') do |_context, payload|
          send_to_js('render', LocalAIRender.render(parse_payload(payload)))
        end

        @dialog.add_action_callback('inspiration_burst') do |_context, payload|
          start_inspiration_burst(parse_payload(payload))
        end

        @dialog.add_action_callback('resume_inspiration_run') do |_context, payload|
          start_resume_inspiration_run(parse_payload(payload))
        end

        @dialog.add_action_callback('cancel_inspiration_burst') do |_context, _payload|
          cancel_inspiration_burst
        end

        @dialog.add_action_callback('verify_pinterest') do |_context, payload|
          start_pinterest_verify(parse_payload(payload))
        end

        @dialog.add_action_callback('open_pinterest_login') do |_context, _payload|
          send_to_js('open_pinterest_login', LocalAIRender.open_pinterest_login)
        end

        @dialog.add_action_callback('set_reference_image') do |_context, payload|
          send_to_js('set_reference_image', LocalAIRender.set_reference_image(parse_payload(payload)))
        end

        @dialog.add_action_callback('edit_result') do |_context, payload|
          send_to_js('edit_result', LocalAIRender.edit_result(parse_payload(payload)))
        end

        @dialog.add_action_callback('upscale_result') do |_context, payload|
          send_to_js('upscale_result', LocalAIRender.upscale_result(parse_payload(payload)))
        end

        @dialog.add_action_callback('download_result') do |_context, payload|
          send_to_js('download_result', LocalAIRender.download_result(parse_payload(payload)))
        end

        @dialog.add_action_callback('delete_history_item') do |_context, payload|
          send_to_js('delete_history_item', LocalAIRender.delete_history_item(parse_payload(payload)))
        end

        @dialog.add_action_callback('delete_history_items') do |_context, payload|
          send_to_js('delete_history_items', LocalAIRender.delete_history_items(parse_payload(payload)))
        end

        @dialog.add_action_callback('load_inspiration_history') do |_context, _payload|
          send_to_js('inspiration_history', LocalAIRender.load_inspiration_history)
        end

        @dialog.add_action_callback('delete_inspiration_runs') do |_context, payload|
          send_to_js('delete_inspiration_runs', LocalAIRender.delete_inspiration_runs(parse_payload(payload)))
        end

        @dialog.add_action_callback('open_path') do |_context, payload|
          data = parse_payload(payload)
          target = data['path'].to_s
          target = data['url'].to_s if target.empty?
          if File.exist?(target)
            UI.openURL(LocalAIRender.file_url(target))
          elsif target =~ %r{\Ahttps?://}i || target.start_with?('file:/')
            UI.openURL(target)
          end
        end
      end

      def parse_payload(payload)
        JSON.parse(payload.to_s.empty? ? '{}' : payload.to_s)
      rescue JSON::ParserError
        {}
      end

      def send_to_js(action, payload)
        script = "window.LocalAIRender.receive(#{JSON.generate(action)}, #{JSON.generate(payload)});"
        @dialog.execute_script(script)
      end

      def start_inspiration_burst(data)
        if @inspiration_thread&.alive?
          send_to_js('inspiration_progress', { ok: false, error: '灵感爆发任务仍在运行，请等待当前任务完成。' })
          return
        end

        LocalAIRender.save_settings(data)
        settings = Settings.to_h
        camera = Camera.snapshot
        image_path = data['image_path'].to_s
        image_path = nil if image_path.empty?

        if truthy?(data['force_capture']) || image_path.nil? || !File.file?(image_path)
          captured = LocalAIRender.capture_view(width: data['capture_width'], height: data['capture_height'])
          unless captured[:ok]
            send_to_js('inspiration_burst', captured)
            return
          end

          image_path = captured[:path]
          send_to_js('inspiration_progress', {
            ok: true,
            stage: 'captured',
            message: '已截取当前白模视口，开始理解空间结构。',
            base_image: {
              path: captured[:path],
              url: captured[:url]
            }
          })
        end

        data['image_path'] = image_path
        data['force_capture'] = false
        data['settings'] = settings
        data['camera'] = camera

        @inspiration_queue = Queue.new
        @inspiration_done = false
        @inspiration_thread = Thread.new do
          begin
            result = LocalAIRender.inspiration_burst(data) do |event|
              @inspiration_queue << ['inspiration_progress', event]
            end
            @inspiration_queue << ['inspiration_burst', result]
          rescue StandardError => e
            @inspiration_queue << [
              'inspiration_burst',
              { ok: false, error: e.message, error_class: e.class.name }
            ]
          ensure
            @inspiration_queue << ['inspiration_complete', { ok: true }]
          end
        end
        start_inspiration_timer
        send_to_js('inspiration_started', {
          ok: true,
          base_image: {
            path: image_path,
            url: LocalAIRender.file_url(image_path)
          }
        })
      end

      def cancel_inspiration_burst
        unless @inspiration_thread&.alive?
          send_to_js('inspiration_progress', { ok: false, error: '当前没有正在运行的灵感爆发任务。' })
          return
        end

        @inspiration_queue ||= Queue.new
        @inspiration_thread.kill
        @inspiration_done = true
        @inspiration_queue << [
          'inspiration_burst',
          { ok: false, cancelled: true, error: '灵感爆发已停止。' }
        ]
        @inspiration_queue << ['inspiration_complete', { ok: true }]
        start_inspiration_timer
      rescue StandardError => e
        send_to_js('inspiration_progress', { ok: false, error: e.message, error_class: e.class.name })
      end

      def start_resume_inspiration_run(data)
        if @inspiration_thread&.alive?
          send_to_js('inspiration_progress', { ok: false, error: '已有灵感爆发任务正在运行，请等待或先停止当前任务。' })
          return
        end

        LocalAIRender.save_settings(data)
        settings = Settings.to_h
        data['settings'] = settings

        @inspiration_queue = Queue.new
        @inspiration_done = false
        @inspiration_thread = Thread.new do
          begin
            result = LocalAIRender.resume_latest_inspiration_run(data) do |event|
              @inspiration_queue << ['inspiration_progress', event]
            end
            @inspiration_queue << ['inspiration_burst', result]
          rescue StandardError => e
            @inspiration_queue << [
              'inspiration_burst',
              { ok: false, error: e.message, error_class: e.class.name }
            ]
          ensure
            @inspiration_queue << ['inspiration_complete', { ok: true }]
          end
        end
        start_inspiration_timer
        send_to_js('inspiration_started', { ok: true })
      end

      def start_inspiration_timer
        UI.stop_timer(@inspiration_timer) if @inspiration_timer
        @inspiration_timer = UI.start_timer(0.25, true) { pump_inspiration_queue }
      end

      def pump_inspiration_queue
        return unless @inspiration_queue

        until @inspiration_queue.empty?
          action, payload = @inspiration_queue.pop(true)
          if action == 'inspiration_complete'
            @inspiration_done = true
            next
          end
          send_to_js(action, payload)
        end

        if @inspiration_done && (!@inspiration_thread || !@inspiration_thread.alive?) && @inspiration_queue.empty?
          UI.stop_timer(@inspiration_timer) if @inspiration_timer
          @inspiration_timer = nil
        end
      rescue ThreadError
        nil
      rescue StandardError => e
        send_to_js('inspiration_progress', { ok: false, error: e.message, error_class: e.class.name })
      end

      def start_pinterest_verify(data)
        request_id = data['verify_request_id'].to_s
        if @pinterest_verify_thread&.alive?
          send_to_js(
            'verify_pinterest',
            {
              ok: true,
              available: false,
              status: 'busy',
              verify_request_id: request_id,
              message: 'Pinterest 验证仍在进行，请稍等。'
            }
          )
          return
        end

        @pinterest_verify_queue = Queue.new
        @pinterest_verify_done = false
        @pinterest_verify_thread = Thread.new do
          started_at = Time.now
          begin
            result = LocalAIRender.verify_pinterest(data)
            result[:verify_request_id] = request_id unless request_id.empty?
            result[:elapsed_seconds] = ((Time.now - started_at) * 10).round / 10.0
            @pinterest_verify_queue << ['verify_pinterest', result]
          rescue StandardError => e
            @pinterest_verify_queue << [
              'verify_pinterest',
              {
                ok: false,
                available: false,
                status: 'error',
                verify_request_id: request_id,
                elapsed_seconds: ((Time.now - started_at) * 10).round / 10.0,
                error: e.message,
                error_class: e.class.name
              }
            ]
          ensure
            @pinterest_verify_queue << ['verify_pinterest_complete', { ok: true }]
          end
        end
        start_pinterest_verify_timer
        send_to_js(
          'verify_pinterest',
          {
            ok: true,
            available: false,
            status: 'checking',
            verify_request_id: request_id,
            message: '正在验证 Pinterest 在线获取...'
          }
        )
      end

      def start_pinterest_verify_timer
        UI.stop_timer(@pinterest_verify_timer) if @pinterest_verify_timer
        @pinterest_verify_timer = UI.start_timer(0.25, true) { pump_pinterest_verify_queue }
      end

      def pump_pinterest_verify_queue
        return unless @pinterest_verify_queue

        until @pinterest_verify_queue.empty?
          action, payload = @pinterest_verify_queue.pop(true)
          if action == 'verify_pinterest_complete'
            @pinterest_verify_done = true
            next
          end
          send_to_js(action, payload)
        end

        if @pinterest_verify_done &&
           (!@pinterest_verify_thread || !@pinterest_verify_thread.alive?) &&
           @pinterest_verify_queue.empty?
          UI.stop_timer(@pinterest_verify_timer) if @pinterest_verify_timer
          @pinterest_verify_timer = nil
        end
      rescue ThreadError
        nil
      rescue StandardError => e
        send_to_js('verify_pinterest', { ok: false, available: false, status: 'error', error: e.message, error_class: e.class.name })
      end

      def truthy?(value)
        value == true || %w[1 true yes on].include?(value.to_s.strip.downcase)
      end

      def settings_payload
        Settings.to_h.merge(
          'plugin_version' => EXTENSION_VERSION,
          'commands' => %w[
            ready
            capture_view
            camera_snapshot
            list_scene_views
            capture_scene_view
            upload_image
            save_settings
            test_api
            test_text_api
            apply_builtin_channel
            update_plugin
            render
            inspiration_burst
            resume_inspiration_run
            cancel_inspiration_burst
            verify_pinterest
            open_pinterest_login
            set_reference_image
            edit_result
            upscale_result
            download_result
            delete_history_item
            delete_history_items
            load_inspiration_history
            delete_inspiration_runs
            open_path
          ]
        )
      end
    end
  end
end
