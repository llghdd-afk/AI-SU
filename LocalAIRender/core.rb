# frozen_string_literal: true

require 'sketchup.rb'
require 'base64'
require 'cgi'
require 'json'
require 'fileutils'
require 'net/http'
require 'openssl'
require 'tmpdir'
require 'uri'

require_relative 'settings'
require_relative 'camera'
require_relative 'api_client'
require_relative 'dialog'

module LLGHD
  module LocalAIRender
    PLUGIN_DIR = File.dirname(__FILE__)
    ROOT_DIR = File.dirname(PLUGIN_DIR)
    PINTEREST_WORKER_PORT = 17_862
    PINTEREST_WORKER_DEBUG_PORT = 17_863
    PINTEREST_WORKER_VERSION = '0.4.8-worker-lens-search'

    class << self
      attr_reader :dialog

      def show_dialog
        @dialog = Dialog.new
        @dialog.show
      end

      def output_root
        path = Thread.current[:local_ai_render_output_dir]
        path = Settings.read('output_dir', default_output_dir) if path.to_s.empty?
        FileUtils.mkdir_p(path)
        path
      end

      def history_mutex
        @history_mutex ||= Mutex.new
      end

      def run_state_mutex
        @run_state_mutex ||= Mutex.new
      end

      def default_output_dir
        File.join(Sketchup.temp_dir, 'llghd_local_ai_render')
      end

      def timestamp
        Time.now.strftime('%Y%m%d-%H%M%S')
      end

      def file_url(path)
        normalized = File.expand_path(path).tr('\\', '/')
        "file:///#{URI::DEFAULT_PARSER.escape(normalized)}"
      end

      def pinterest_worker_base_url
        "http://127.0.0.1:#{PINTEREST_WORKER_PORT}"
      end

      def pinterest_worker_login_url
        "#{pinterest_worker_base_url}/login"
      end

      def capture_view(width: nil, height: nil)
        model = Sketchup.active_model
        view = model.active_view
        width = positive_int(width, Settings.read('capture_width', 1280))
        height = positive_int(height, Settings.read('capture_height', 900))
        path = File.join(output_root, "capture-#{timestamp}.png")

        write_view_image(view, path, width, height)

        {
          ok: true,
          path: path,
          url: file_url(path),
          width: width,
          height: height,
          camera: Camera.snapshot
        }
      rescue StandardError => e
        error_result(e)
      end

      def list_scene_views(width: nil, height: nil, offset: nil, limit: nil)
        model = Sketchup.active_model
        pages = model.pages.to_a
        return { ok: false, error: '当前模型没有可选场景。请先在 SketchUp 中创建场景。' } if pages.empty?

        width = positive_int(width, 240)
        height = positive_int(height, 150)
        offset = positive_int(offset, 0)
        limit = positive_int(limit, 6)
        limit = [[limit, 1].max, 8].min
        dir = File.join(output_root, 'scene_thumbnails')
        FileUtils.mkdir_p(dir)
        batch_id = timestamp
        views = []
        page_batch = pages.each_with_index.to_a.slice(offset, limit) || []

        preserve_active_view do
          page_batch.each do |page, index|
            next unless page.respond_to?(:camera)

            activate_page(page)
            path = File.join(dir, "scene-#{batch_id}-#{index + 1}.png")
            write_view_image(model.active_view, path, width, height, antialias: false)

            views << {
              id: index,
              page_index: index,
              name: page.name.to_s.empty? ? "场景#{index + 1}" : page.name.to_s,
              path: path,
              url: file_url(path),
              camera: Camera.from_camera(page.camera, model, model.active_view, page.name.to_s)
            }
          end
        end

        {
          ok: true,
          views: views,
          offset: offset,
          limit: limit,
          total: pages.length,
          next_offset: offset + limit,
          has_more: offset + limit < pages.length
        }
      rescue StandardError => e
        error_result(e)
      end

      def capture_scene_view(page_index:, width: nil, height: nil)
        model = Sketchup.active_model
        pages = model.pages.to_a
        index = Integer(page_index)
        page = pages[index]
        raise ArgumentError, 'Selected scene no longer exists.' unless page

        width = positive_int(width, Settings.read('capture_width', 1280))
        height = positive_int(height, Settings.read('capture_height', 900))
        dir = File.join(output_root, 'scene_captures')
        FileUtils.mkdir_p(dir)
        path = File.join(dir, "scene-input-#{timestamp}-#{index + 1}.png")
        camera = nil

        preserve_active_view do
          activate_page(page)
          write_view_image(model.active_view, path, width, height)
          camera = Camera.from_camera(page.camera, model, model.active_view, page.name.to_s)
        end

        {
          ok: true,
          path: path,
          url: file_url(path),
          width: width,
          height: height,
          scene: page.name.to_s,
          camera: camera
        }
      rescue StandardError => e
        error_result(e)
      end

      def save_uploaded_data_url(data_url, original_name = nil)
        unless data_url.to_s.start_with?('data:image/')
          raise ArgumentError, 'Only image data URLs are supported.'
        end

        header, encoded = data_url.split(',', 2)
        mime = header[/data:(.*?);base64/, 1] || 'image/png'
        ext = mime.include?('jpeg') ? 'jpg' : mime.split('/').last.to_s.gsub(/[^a-z0-9]/i, '')
        ext = 'png' if ext.empty?
        safe_name = sanitize_filename(original_name.to_s)
        safe_name = "upload-#{timestamp}.#{ext}" if safe_name.empty?
        safe_name = "#{File.basename(safe_name, '.*')}.#{ext}" unless safe_name.downcase.end_with?(".#{ext.downcase}")

        dir = File.join(output_root, 'uploads')
        FileUtils.mkdir_p(dir)
        path = File.join(dir, safe_name)
        File.binwrite(path, Base64.decode64(encoded.to_s))

        {
          ok: true,
          path: path,
          url: file_url(path),
          camera: Camera.snapshot
        }
      rescue StandardError => e
        error_result(e)
      end

      def render(payload)
        save_settings(payload) if payload.is_a?(Hash)
        prompt = payload['prompt'].to_s.strip
        image_path = payload['image_path'].to_s
        image_path = nil if image_path.empty?
        raise ArgumentError, 'Please capture or upload an image first.' if image_path.nil? || !File.file?(image_path)

        settings = Settings.to_h
        client = ApiClient.new(settings)
        result = client.render(
          prompt: prompt,
          image_path: image_path,
          camera: Camera.snapshot,
          options: payload
        )
        result = persist_result(result, payload, action: 'render')
        result.merge(ok: true)
      rescue StandardError => e
        error_result(e)
      end

      def inspiration_burst(payload, &progress)
        payload = {} unless payload.is_a?(Hash)
        save_settings(payload) unless payload['settings'].is_a?(Hash)

        count = [[positive_int(payload['target_count'], 4), 2].max, 12].min
        base_note = payload['prompt'].to_s.strip
        base_note = '根据当前 SketchUp 白模寻找客户提案灵感，输出多套不同材质、灯光和软装方向的写实效果图。' if base_note.empty?

        image_path = payload['image_path'].to_s
        image_path = nil if image_path.empty?
        if truthy?(payload['force_capture']) || image_path.nil? || !File.file?(image_path)
          captured = capture_view(width: payload['capture_width'], height: payload['capture_height'])
          raise captured[:error].to_s unless captured[:ok]

          image_path = captured[:path]
        end

        settings = payload['settings'].is_a?(Hash) ? payload['settings'] : Settings.to_h
        Thread.current[:local_ai_render_output_dir] = settings['output_dir'].to_s unless settings['output_dir'].to_s.empty?
        references = []
        client = ApiClient.new(settings)
        camera = payload['camera'].is_a?(Hash) ? payload['camera'] : Camera.snapshot
        emit_progress(
          progress,
          stage: 'analyzing',
          message: "正在用 #{Array(text_model_candidates(settings, primary_key: 'planner_model', default_model: 'gpt-5.5')).first || 'gpt-5.5'} 总结白模并生成 Pinterest 搜索词...",
          base_image: { path: image_path, url: file_url(image_path) },
          target_count: count
        )
        plan = build_inspiration_plan(
          client: client,
          image_path: image_path,
          base_note: base_note,
          count: count,
          references: references,
          settings: settings
        )
        emit_progress(
          progress,
          stage: 'pinterest_plan',
          message: '已生成 Pinterest 搜索词和版本方向。',
          plan: plan,
          target_count: count
        )
        emit_progress(
          progress,
          stage: 'pinterest_fetch',
          message: '正在由工具在线获取 Pinterest 灵感图...',
          plan: plan,
          target_count: count
        )
        references = fetch_online_pinterest_references(
          plan: plan,
          count: count,
          progress: progress,
          base_image_path: image_path,
          use_lens: truthy?(payload['use_pinterest_lens'])
        )
        references = enrich_pinterest_references(
          client: client,
          base_image_path: image_path,
          references: references,
          plan: plan,
          progress: progress,
          settings: settings
        )
        emit_progress(
          progress,
          stage: 'pinterest_images',
          message: "Pinterest 灵感图获取完成：#{references.count { |item| !item['path'].to_s.empty? }}/#{count}",
          references: references,
          plan: plan,
          target_count: count
        )
        results = []
        run_id = "inspiration-#{timestamp}"

        jobs = count.times.map do |index|
          version = index + 1
          prompt = inspiration_version_prompt(
            base_note: base_note,
            index: version,
            total: count,
            references: references,
            plan: plan
          )
          version_payload = payload.merge(
            'prompt' => prompt,
            'image_path' => image_path,
            'inspiration_version' => version,
            'inspiration_total' => count
          )
          source = inspiration_source(index: version, references: references, plan: plan)
          {
            index: version,
            prompt: prompt,
            payload: version_payload,
            source: source
          }
        end

        jobs.each do |job|
          upsert_inspiration_result(results, {
            ok: nil,
            pending: true,
            status: 'pending',
            index: job[:index],
            prompt: job[:prompt],
            inspiration_source: job[:source]
          })
        end
        persist_inspiration_run_state(
          run_id,
          target_count: count,
          base_image_path: image_path,
          plan: plan,
          references: references,
          results: results
        )

        network_ready = ensure_render_api_ready(client: client, progress: progress, target_count: count)
        work_queue = Queue.new
        jobs.each { |job| work_queue << job }
        result_mutex = Mutex.new
        worker_count = network_ready ? [[count, 2].min, 1].max : 1
        workers = worker_count.times.map do
          Thread.new do
            worker_client = ApiClient.new(settings)
            loop do
              job = begin
                work_queue.pop(true)
              rescue ThreadError
                nil
              end
              break unless job

              version = job[:index]
              prompt = job[:prompt]
              version_payload = job[:payload]
              source = job[:source]
              rendering_item = {
                ok: nil,
                pending: true,
                status: 'rendering',
                index: version,
                prompt: prompt,
                inspiration_source: source
              }
              result_mutex.synchronize do
                upsert_inspiration_result(results, rendering_item)
                persist_inspiration_run_state(
                  run_id,
                  target_count: count,
                  base_image_path: image_path,
                  plan: plan,
                  references: references,
                  results: results
                )
              end

          emit_progress(
            progress,
            stage: 'rendering',
            message: "正在渲染第 #{version}/#{count} 个灵感版本...",
            index: version,
            target_count: count,
            prompt: prompt,
                source: source,
                result: rendering_item
          )

          begin
            result = render_inspiration_version(
                  client: worker_client,
              prompt: prompt,
              image_path: image_path,
              camera: camera,
              options: version_payload,
              version: version,
              count: count,
              progress: progress
            )
            persisted = persist_result(result, version_payload, action: 'inspiration_burst', settings: settings)
            item = {
              ok: true,
              index: version,
              prompt: prompt,
              image_path: persisted[:image_path] || persisted['image_path'],
              image_url: persisted[:image_url] || persisted['image_url'],
              inspiration_source: source,
              history_record: persisted[:history_record] || persisted['history_record']
            }
                item[:history_error] = persisted[:history_error] || persisted['history_error'] if persisted[:history_error] || persisted['history_error']
                result_mutex.synchronize do
                  upsert_inspiration_result(results, item)
                  persist_inspiration_run_state(
                    run_id,
                    target_count: count,
                    base_image_path: image_path,
                    plan: plan,
                    references: references,
                    results: results
                  )
                end
            emit_progress(
              progress,
              stage: 'rendered',
              message: "第 #{version}/#{count} 个版本已完成。",
              index: version,
              target_count: count,
              result: item
            )
          rescue StandardError => e
            retryable = retryable_render_error?(e)
            item = {
              ok: false,
              status: retryable ? 'network_failed' : 'failed',
              retryable: retryable,
              index: version,
              prompt: prompt,
              inspiration_source: source,
              error: e.message,
              error_class: e.class.name
            }
                result_mutex.synchronize do
                  upsert_inspiration_result(results, item)
                  persist_inspiration_run_state(
                    run_id,
                    target_count: count,
                    base_image_path: image_path,
                    plan: plan,
                    references: references,
                    results: results
                  )
                end
            emit_progress(
              progress,
              stage: 'render_failed',
              message: "第 #{version}/#{count} 个版本失败。",
              index: version,
              target_count: count,
              result: item
            )
              end
            end
          end
        end
        workers.each(&:join)

        2.times do |recovery_round|
          network_failed_indices = results.select { |item| item[:ok] == false && item[:retryable] }.map { |item| item[:index].to_i }.sort
          break if network_failed_indices.empty?

          cooldown_seconds = recovery_round.zero? ? 15 : 35
          emit_progress(
            progress,
            stage: 'render_retry',
            message: "检测到 #{network_failed_indices.length} 个版本因网络波动失败，等待 #{cooldown_seconds} 秒后自动补跑第 #{recovery_round + 1}/2 轮...",
            target_count: count
          )
          sleep cooldown_seconds
          ensure_render_api_ready(client: client, progress: progress, target_count: count) if recovery_round.positive?
          recovery_client = ApiClient.new(settings)
          network_failed_indices.each do |version|
            job = jobs.find { |candidate| candidate[:index].to_i == version }
            next unless job

            prompt = job[:prompt]
            version_payload = job[:payload]
            source = job[:source]
            recovery_item = {
              ok: nil,
              pending: true,
              status: 'network_retrying',
              index: version,
              prompt: prompt,
              inspiration_source: source
            }
            result_mutex.synchronize do
              upsert_inspiration_result(results, recovery_item)
              persist_inspiration_run_state(
                run_id,
                target_count: count,
                base_image_path: image_path,
                plan: plan,
                references: references,
                results: results
              )
            end
            emit_progress(
              progress,
              stage: 'render_retry',
              message: "正在补跑第 #{version}/#{count} 个网络失败版本...",
              index: version,
              target_count: count,
              result: recovery_item
            )

            begin
              result = render_inspiration_version(
                client: recovery_client,
                prompt: prompt,
                image_path: image_path,
                camera: camera,
                options: version_payload,
                version: version,
                count: count,
                progress: progress
              )
              persisted = persist_result(result, version_payload, action: 'inspiration_burst', settings: settings)
              item = {
                ok: true,
                index: version,
                prompt: prompt,
                image_path: persisted[:image_path] || persisted['image_path'],
                image_url: persisted[:image_url] || persisted['image_url'],
                inspiration_source: source,
                history_record: persisted[:history_record] || persisted['history_record']
              }
              item[:history_error] = persisted[:history_error] || persisted['history_error'] if persisted[:history_error] || persisted['history_error']
              result_mutex.synchronize do
                upsert_inspiration_result(results, item)
                persist_inspiration_run_state(
                  run_id,
                  target_count: count,
                  base_image_path: image_path,
                  plan: plan,
                  references: references,
                  results: results
                )
              end
              emit_progress(
                progress,
                stage: 'rendered',
                message: "第 #{version}/#{count} 个网络失败版本补跑成功。",
                index: version,
                target_count: count,
                result: item
              )
            rescue StandardError => e
              retryable = retryable_render_error?(e)
              item = {
                ok: false,
                status: retryable ? 'network_failed' : 'failed',
                retryable: retryable,
                index: version,
                prompt: prompt,
                inspiration_source: source,
                error: e.message,
                error_class: e.class.name
              }
              result_mutex.synchronize do
                upsert_inspiration_result(results, item)
                persist_inspiration_run_state(
                  run_id,
                  target_count: count,
                  base_image_path: image_path,
                  plan: plan,
                  references: references,
                  results: results
                )
              end
              emit_progress(
                progress,
                stage: 'render_failed',
                message: "第 #{version}/#{count} 个版本第 #{recovery_round + 1}/2 轮补跑后仍失败。",
                index: version,
                target_count: count,
                result: item
              )
            end
          end
        end

        generated_count = results.count { |item| item[:ok] || item['ok'] }
        failed_count = results.count { |item| (item.key?(:ok) ? item[:ok] : item['ok']) == false }
        final_result = {
          ok: true,
          action: 'inspiration_burst',
          run_id: run_id,
          run_log_path: inspiration_run_path(run_id),
          target_count: count,
          generated_count: generated_count,
          failed_count: failed_count,
          complete: generated_count >= count,
          base_image: {
            path: image_path,
            url: file_url(image_path)
          },
          references: references,
          plan: plan,
          results: results,
          history: history_records
        }
        persist_inspiration_run_state(
          run_id,
          target_count: count,
          base_image_path: image_path,
          plan: plan,
          references: references,
          results: results,
          complete: generated_count >= count
        )
        final_result
      rescue StandardError => e
        error_result(e)
      ensure
        Thread.current[:local_ai_render_output_dir] = nil
      end

      def resume_latest_inspiration_run(payload, &progress)
        payload = {} unless payload.is_a?(Hash)
        save_settings(payload) unless payload['settings'].is_a?(Hash)
        settings = payload['settings'].is_a?(Hash) ? payload['settings'] : Settings.to_h
        Thread.current[:local_ai_render_output_dir] = settings['output_dir'].to_s unless settings['output_dir'].to_s.empty?

        run_path = latest_inspiration_run_file
        raise '没有找到可补齐的灵感爆发批次。' unless run_path && File.file?(run_path)

        run = JSON.parse(File.read(run_path, encoding: 'UTF-8'))
        run_id = run['run_id'].to_s.empty? ? File.basename(run_path, '.json') : run['run_id'].to_s
        target_count = positive_int(run['target_count'], 0)
        results = Array(run['results']).select { |item| item.is_a?(Hash) }
        target_count = results.length if target_count <= 0
        target_count = [[target_count, 2].max, 24].min
        base_image_path = run.dig('base_image', 'path').to_s
        raise '上次批次的白模基础图已不存在，无法补齐。' unless File.file?(base_image_path)

        plan = run['plan'].is_a?(Hash) ? run['plan'] : {}
        references = Array(run['references'])
        client = ApiClient.new(settings)
        camera = payload['camera'].is_a?(Hash) ? payload['camera'] : Camera.snapshot

        emit_progress(
          progress,
          stage: 'render',
          message: "已读取上次批次 #{run_id}，正在检查未完成版本...",
          base_image: { path: base_image_path, url: file_url(base_image_path) },
          plan: plan,
          references: references,
          target_count: target_count
        )

        jobs = []
        (1..target_count).each do |version|
          existing = results.find { |item| item['index'].to_i == version }
          next if existing && existing['ok']

          prompt = existing && existing['prompt'].to_s
          prompt = inspiration_version_prompt(
            base_note: payload['prompt'].to_s.empty? ? '补齐上次未完成的灵感爆发效果图。' : payload['prompt'].to_s,
            index: version,
            total: target_count,
            references: references,
            plan: plan
          ) if prompt.to_s.empty?
          source = existing && existing['inspiration_source'].is_a?(Hash) ? existing['inspiration_source'] : inspiration_source(index: version, references: references, plan: plan)
          version_payload = payload.merge(
            'prompt' => prompt,
            'image_path' => base_image_path,
            'inspiration_version' => version,
            'inspiration_total' => target_count,
            'force_capture' => false
          )
          jobs << { index: version, prompt: prompt, payload: version_payload, source: source }
          upsert_inspiration_result(results, {
            ok: nil,
            pending: true,
            status: 'resume_pending',
            index: version,
            prompt: prompt,
            inspiration_source: source
          })
        end

        persist_inspiration_run_state(
          run_id,
          target_count: target_count,
          base_image_path: base_image_path,
          plan: plan,
          references: references,
          results: results
        )

        if jobs.empty?
          generated_count = results.count { |item| item['ok'] || item[:ok] }
          failed_count = results.count { |item| (item.key?('ok') ? item['ok'] : item[:ok]) == false }
          return {
            ok: true,
            action: 'inspiration_burst',
            resumed: true,
            run_id: run_id,
            run_log_path: run_path,
            target_count: target_count,
            generated_count: generated_count,
            failed_count: failed_count,
            complete: generated_count >= target_count,
            base_image: { path: base_image_path, url: file_url(base_image_path) },
            references: references,
            plan: plan,
            results: results,
            history: history_records
          }
        end

        network_ready = ensure_render_api_ready(client: client, progress: progress, target_count: target_count)
        emit_progress(
          progress,
          stage: 'render',
          message: "将补齐 #{jobs.length} 个未完成版本#{network_ready ? '。' : '；接口预检不稳，使用单线程稳妥补跑。'}",
          target_count: target_count,
          results: results
        )

        jobs.each_with_index do |job, offset|
          if offset.positive? && (offset % 4).zero?
            emit_progress(
              progress,
              stage: 'render_preflight',
              message: '长队列补齐冷却 10 秒，并重新检查渲染接口...',
              target_count: target_count
            )
            sleep 10
            ensure_render_api_ready(client: client, progress: progress, target_count: target_count)
          end

          version = job[:index]
          prompt = job[:prompt]
          version_payload = job[:payload]
          source = job[:source]
          running_item = {
            ok: nil,
            pending: true,
            status: 'network_retrying',
            index: version,
            prompt: prompt,
            inspiration_source: source
          }
          upsert_inspiration_result(results, running_item)
          persist_inspiration_run_state(
            run_id,
            target_count: target_count,
            base_image_path: base_image_path,
            plan: plan,
            references: references,
            results: results
          )
          emit_progress(
            progress,
            stage: 'render_retry',
            message: "正在补齐第 #{version}/#{target_count} 个版本...",
            index: version,
            target_count: target_count,
            result: running_item
          )

          begin
            result = render_inspiration_version(
              client: client,
              prompt: prompt,
              image_path: base_image_path,
              camera: camera,
              options: version_payload,
              version: version,
              count: target_count,
              progress: progress
            )
            persisted = persist_result(result, version_payload, action: 'inspiration_burst', settings: settings)
            item = {
              ok: true,
              index: version,
              prompt: prompt,
              image_path: persisted[:image_path] || persisted['image_path'],
              image_url: persisted[:image_url] || persisted['image_url'],
              inspiration_source: source,
              history_record: persisted[:history_record] || persisted['history_record']
            }
            item[:history_error] = persisted[:history_error] || persisted['history_error'] if persisted[:history_error] || persisted['history_error']
            upsert_inspiration_result(results, item)
            emit_progress(
              progress,
              stage: 'rendered',
              message: "第 #{version}/#{target_count} 个版本已补齐。",
              index: version,
              target_count: target_count,
              result: item
            )
          rescue StandardError => e
            retryable = retryable_render_error?(e)
            item = {
              ok: false,
              status: retryable ? 'network_failed' : 'failed',
              retryable: retryable,
              index: version,
              prompt: prompt,
              inspiration_source: source,
              error: e.message,
              error_class: e.class.name
            }
            upsert_inspiration_result(results, item)
            emit_progress(
              progress,
              stage: 'render_failed',
              message: "第 #{version}/#{target_count} 个版本补齐失败。",
              index: version,
              target_count: target_count,
              result: item
            )
          ensure
            persist_inspiration_run_state(
              run_id,
              target_count: target_count,
              base_image_path: base_image_path,
              plan: plan,
              references: references,
              results: results
            )
          end
        end

        generated_count = results.count { |item| item['ok'] || item[:ok] }
        failed_count = results.count { |item| (item.key?('ok') ? item['ok'] : item[:ok]) == false }
        final_result = {
          ok: true,
          action: 'inspiration_burst',
          resumed: true,
          run_id: run_id,
          run_log_path: run_path,
          target_count: target_count,
          generated_count: generated_count,
          failed_count: failed_count,
          complete: generated_count >= target_count,
          base_image: { path: base_image_path, url: file_url(base_image_path) },
          references: references,
          plan: plan,
          results: results,
          history: history_records
        }
        persist_inspiration_run_state(
          run_id,
          target_count: target_count,
          base_image_path: base_image_path,
          plan: plan,
          references: references,
          results: results,
          complete: generated_count >= target_count
        )
        final_result
      rescue JSON::ParserError => e
        error_result(e)
      ensure
        Thread.current[:local_ai_render_output_dir] = nil
      end

      def set_reference_image(payload)
        path = ensure_local_image(payload, folder: 'references', prefix: 'reference')
        {
          ok: true,
          path: path,
          url: file_url(path),
          camera: Camera.snapshot
        }
      rescue StandardError => e
        error_result(e)
      end

      def edit_result(payload)
        path = ensure_local_image(payload, folder: 'edits', prefix: 'edit-source')
        {
          ok: true,
          path: path,
          url: file_url(path),
          camera: Camera.snapshot,
          edit_mode: true
        }
      rescue StandardError => e
        error_result(e)
      end

      def upscale_result(payload)
        save_settings(payload) if payload.is_a?(Hash)
        image_path = ensure_local_image(payload, folder: 'upscale_sources', prefix: 'upscale-source')
        settings = Settings.to_h
        client = ApiClient.new(settings)
        prompt = payload['prompt'].to_s.strip
        prompt = upscale_prompt if prompt.empty?
        result = client.render(
          prompt: prompt,
          image_path: image_path,
          camera: Camera.snapshot,
          options: payload.merge('size' => 'auto')
        )
        result = persist_result(result, payload.merge('prompt' => prompt), action: 'upscale')
        result.merge(ok: true, action: 'upscale')
      rescue StandardError => e
        error_result(e)
      end

      def load_history
        { ok: true, history: history_records }
      rescue StandardError => e
        error_result(e)
      end

      def load_inspiration_history
        { ok: true, inspiration_history: inspiration_history_records }
      rescue StandardError => e
        error_result(e)
      end

      def delete_history_item(payload)
        delete_history_items(payload)
      end

      def delete_history_items(payload)
        payload = {} unless payload.is_a?(Hash)
        ids = payload_values(payload, 'ids') + payload_values(payload, 'id')
        paths = payload_values(payload, 'paths') + payload_values(payload, 'path')
        if ids.empty? && paths.empty?
          return { ok: true, history: history_records, deleted_count: 0, deleted_files: 0 }
        end

        deleted_count = 0
        deleted_files = 0
        remaining = []
        history_mutex.synchronize do
          records = history_records
          remaining = records.reject do |record|
            matched = history_record_selected?(record, ids, paths)
            if matched
              deleted_count += 1
              deleted_files += 1 if safe_delete_output_file(record['path'])
            end
            matched
          end
          write_history(remaining)
        end
        { ok: true, history: history_records, deleted_count: deleted_count, deleted_files: deleted_files }
      rescue StandardError => e
        error_result(e)
      end

      def delete_inspiration_runs(payload)
        payload = {} unless payload.is_a?(Hash)
        run_ids = payload_values(payload, 'run_ids') + payload_values(payload, 'run_id') + payload_values(payload, 'ids')
        if run_ids.empty?
          return { ok: true, inspiration_history: inspiration_history_records, deleted_count: 0, deleted_files: 0 }
        end

        deleted_count = 0
        deleted_files = 0
        run_ids.uniq.each do |run_id|
          path = inspiration_run_path(sanitize_run_id(run_id))
          next unless File.file?(path)

          data = JSON.parse(File.read(path, encoding: 'UTF-8'))
          inspiration_file_paths(data).each do |file_path|
            deleted_files += 1 if safe_delete_output_file(file_path)
          end
          deleted_files += 1 if safe_delete_output_file(path)
          deleted_count += 1
        rescue JSON::ParserError
          deleted_files += 1 if safe_delete_output_file(path)
          deleted_count += 1
        end

        history_mutex.synchronize { write_history(history_records) }
        {
          ok: true,
          inspiration_history: inspiration_history_records,
          history: history_records,
          deleted_count: deleted_count,
          deleted_files: deleted_files
        }
      rescue StandardError => e
        error_result(e)
      end

      def download_result(payload)
        source_path = ensure_local_image(payload, folder: 'download_sources', prefix: 'download-source')
        dest_path = copy_image(source_path, folder: 'downloads', prefix: 'render-download')
        {
          ok: true,
          path: dest_path,
          url: file_url(dest_path)
        }
      rescue StandardError => e
        error_result(e)
      end

      def test_api(payload)
        save_settings(payload) if payload.is_a?(Hash)
        settings = Settings.to_h
        client = ApiClient.new(settings)
        client.test_connection
      rescue StandardError => e
        error_result(e)
      end

      def test_text_api(payload)
        save_settings(payload) if payload.is_a?(Hash)
        settings = Settings.to_h
        errors = []
        text_request_routes(settings, primary_key: 'planner_model', default_model: 'gpt-5.5').each do |route|
          begin
            result = ApiClient.new(route[:settings]).test_chat_connection(text_model: route[:model])
            return result.merge(
              ok: true,
              channel: route[:label],
              model: route[:model],
              message: "分析接口可用：#{route[:label]} / #{route[:model]}"
            )
          rescue StandardError => e
            errors << "#{route[:label]} #{route[:model]}: #{e.message}"
          end
        end
        raise(errors.join(' | '))
      rescue StandardError => e
        error_result(e)
      end

      def apply_builtin_channel
        channel = Settings.builtin_channel
        %w[endpoint api_key model request_mode].each do |key|
          Settings.write(key, channel[key])
        end
        { ok: true, settings: Settings.to_h, channel: channel.reject { |key, _| key == 'api_key' } }
      rescue StandardError => e
        error_result(e)
      end

      def update_plugin(payload)
        save_settings(payload) if payload.is_a?(Hash)
        settings = Settings.to_h
        url = settings['github_direct_url'].to_s.strip
        url = github_release_asset_url(settings) if url.empty?
        raise '没有可用的 GitHub 更新地址。请填写仓库和发布包文件名，或直接填写下载地址。' if url.empty?

        work_dir = Dir.mktmpdir('local-ai-render-update-')
        zip_path = File.join(work_dir, 'update.zip')
        extract_dir = File.join(work_dir, 'extracted')
        FileUtils.mkdir_p(extract_dir)
        download_update_archive(url, zip_path)
        expand_update_archive(zip_path, extract_dir)
        source_root = find_update_source_root(extract_dir)
        backup_dir = backup_current_plugin
        install_update_source(source_root)
        {
          ok: true,
          message: "更新文件已写入本机插件目录，已备份当前版本到 #{backup_dir}。请完全重启 SketchUp 后生效。",
          backup_dir: backup_dir,
          source_url: url,
          plugin_version: EXTENSION_VERSION
        }
      rescue StandardError => e
        error_result(e)
      ensure
        FileUtils.remove_entry(work_dir) if defined?(work_dir) && work_dir && Dir.exist?(work_dir)
      end

      def github_release_asset_url(settings)
        repo = settings['github_repo'].to_s.strip
        asset = settings['github_asset'].to_s.strip
        asset = 'LocalAIRender.zip' if asset.empty?
        raise 'GitHub 仓库格式应为 owner/repo。' unless repo =~ %r{\A[\w.-]+/[\w.-]+\z}

        response = http_get_follow(
          URI("https://api.github.com/repos/#{repo}/releases/latest"),
          headers: github_headers,
          open_timeout: 15,
          read_timeout: 45
        )
        unless response.is_a?(Net::HTTPSuccess)
          raise "GitHub 最新发布读取失败：HTTP #{response.code} #{response.body.to_s[0, 300]}"
        end

        release = JSON.parse(response.body.to_s)
        assets = Array(release['assets'])
        match = assets.find { |item| item.is_a?(Hash) && item['name'].to_s == asset }
        match ||= assets.find { |item| item.is_a?(Hash) && item['name'].to_s.downcase == asset.downcase }
        unless match && !match['browser_download_url'].to_s.empty?
          visible = assets.map { |item| item.is_a?(Hash) ? item['name'].to_s : '' }.reject(&:empty?).first(8)
          raise "GitHub 最新发布里没有找到 #{asset}。当前可见发布包：#{visible.empty? ? '无' : visible.join(', ')}"
        end

        match['browser_download_url'].to_s
      end

      def download_update_archive(url, zip_path)
        response = http_get_follow(
          URI(url),
          headers: github_headers,
          open_timeout: 20,
          read_timeout: 300
        )
        unless response.is_a?(Net::HTTPSuccess)
          raise "更新包下载失败：HTTP #{response.code} #{response.body.to_s[0, 300]}"
        end

        File.binwrite(zip_path, response.body)
        raise '更新包下载为空。' if File.size(zip_path).zero?

        zip_path
      end

      def expand_update_archive(zip_path, extract_dir)
        command = "Expand-Archive -LiteralPath #{powershell_quote(zip_path)} -DestinationPath #{powershell_quote(extract_dir)} -Force"
        ok = system('powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', command)
        raise '更新包解压失败，请确认下载的是 zip/rbz 发布包。' unless ok

        extract_dir
      end

      def find_update_source_root(extract_dir)
        candidates = [extract_dir]
        Dir.glob(File.join(extract_dir, '**', 'LocalAIRender.rb')).each do |loader|
          candidates << File.dirname(loader)
        end
        root = candidates.uniq.find do |candidate|
          File.file?(File.join(candidate, 'LocalAIRender.rb')) &&
            Dir.exist?(File.join(candidate, 'LocalAIRender')) &&
            File.file?(File.join(candidate, 'LocalAIRender', 'core.rb')) &&
            File.file?(File.join(candidate, 'LocalAIRender', 'ui.html'))
        end
        raise '更新包结构不匹配：需要包含 LocalAIRender.rb 和 LocalAIRender/ 目录。' unless root

        root
      end

      def backup_current_plugin
        backup_dir = File.join(output_root, 'plugin_backups', "LocalAIRender-#{timestamp}")
        FileUtils.mkdir_p(backup_dir)
        loader = File.join(ROOT_DIR, 'LocalAIRender.rb')
        FileUtils.cp(loader, File.join(backup_dir, 'LocalAIRender.rb')) if File.file?(loader)
        FileUtils.cp_r(PLUGIN_DIR, File.join(backup_dir, 'LocalAIRender')) if Dir.exist?(PLUGIN_DIR)
        backup_dir
      end

      def install_update_source(source_root)
        source_loader = File.join(source_root, 'LocalAIRender.rb')
        source_dir = File.join(source_root, 'LocalAIRender')
        target_loader = File.join(ROOT_DIR, 'LocalAIRender.rb')
        target_dir = PLUGIN_DIR
        raise '更新包缺少 LocalAIRender.rb。' unless File.file?(source_loader)
        raise '更新包缺少 LocalAIRender 目录。' unless Dir.exist?(source_dir)
        raise '插件安装目录异常，无法写入更新。' unless File.expand_path(target_loader).start_with?(File.expand_path(ROOT_DIR))
        raise '插件安装目录异常，无法写入更新。' unless File.expand_path(target_dir).start_with?(File.expand_path(ROOT_DIR))

        FileUtils.mkdir_p(target_dir)
        FileUtils.cp(source_loader, target_loader)
        FileUtils.cp_r(Dir.glob(File.join(source_dir, '*')), target_dir)
      end

      def github_headers
        {
          'User-Agent' => 'LLGHD-LocalAIRender-Updater',
          'Accept' => 'application/vnd.github+json, application/octet-stream'
        }
      end

      def powershell_quote(value)
        "'#{value.to_s.gsub("'", "''")}'"
      end

      def verify_pinterest(payload = {})
        payload ||= {}
        request_id = payload['verify_request_id'].to_s
        started_at = Time.now
        query = payload['query'].to_s.strip
        query = 'modern interior design inspiration' if query.empty?
        search_url = pinterest_search_url(query)
        login_url = start_pinterest_worker ? pinterest_worker_login_url : 'https://www.pinterest.com/login/'
        pinterest_error = nil
        urls = begin
          pinterest_worker_image_urls(query, count: 12).first(12)
        rescue StandardError => e
          pinterest_error = e
          []
        end
        result = {
          ok: true,
          query: query,
          search_url: search_url,
          login_url: login_url,
          image_count: urls.length,
          sample_url: urls.first.to_s,
          elapsed_seconds: ((Time.now - started_at) * 10).round / 10.0
        }
        result[:verify_request_id] = request_id unless request_id.empty?

        if urls.empty?
          return result.merge(
            available: false,
            status: 'pinterest_unavailable',
            error: pinterest_error&.message.to_s,
            message: '当前没有拿到 Pinterest 网站灵感图。可能是 worker 未返回图片、网络/代理超时，或 Pinterest 登录态失效；可以先点“打开 Pinterest 登录”确认专用 Chrome 中是否仍已登录，再重新验证。'
          )
        end

        result.merge(
          available: true,
          status: 'ready',
          message: '已验证：当前工具可以从 Pinterest 页面获取真实灵感图 URL。'
        )
      rescue StandardError => e
        {
          ok: false,
          available: false,
          status: 'error',
          verify_request_id: request_id.to_s,
          elapsed_seconds: ((Time.now - started_at) * 10).round / 10.0,
          error: e.message,
          error_class: e.class.name,
          query: query.to_s,
          search_url: search_url.to_s.empty? ? pinterest_search_url(query.to_s) : search_url.to_s,
          login_url: 'https://www.pinterest.com/login/',
          message: 'Pinterest 验证失败。'
        }
      end

      def open_pinterest_login
        raise 'Pinterest worker 启动失败。' unless start_pinterest_worker

        response = http_get_follow(
          URI(pinterest_worker_login_url),
          headers: {},
          open_timeout: 2,
          read_timeout: 8
        )
        {
          ok: response.is_a?(Net::HTTPSuccess),
          status: response.code.to_i,
          login_url: pinterest_worker_login_url,
          message: response.is_a?(Net::HTTPSuccess) ? '已打开插件专用 Pinterest 登录窗口。' : "Pinterest 登录窗口打开失败：HTTP #{response.code}"
        }
      rescue StandardError => e
        error_result(e)
      end

      def save_settings(payload)
        %w[endpoint api_key model output_dir capture_width capture_height request_mode text_endpoint text_api_key planner_model reference_model backup_text_models backup_text_endpoints backup_text_api_keys github_repo github_asset github_direct_url].each do |key|
          Settings.write(key, payload[key]) if payload.key?(key)
        end
        { ok: true, settings: Settings.to_h }
      rescue StandardError => e
        error_result(e)
      end

      def error_result(error)
        {
          ok: false,
          error: error.message,
          error_class: error.class.name
        }
      end

      def sanitize_filename(name)
        File.basename(name).gsub(/[^\w.\-]/, '_')
      end

      def positive_int(value, fallback)
        parsed = Integer(value)
        parsed.positive? ? parsed : fallback
      rescue StandardError
        fallback
      end

      def truthy?(value)
        value == true || %w[1 true yes on].include?(value.to_s.strip.downcase)
      end

      def save_inspiration_references(references)
        saved = []
        Array(references).first(12).each_with_index do |reference, index|
          begin
            payload = if reference.is_a?(Hash)
                        {
                          'path' => reference['path'],
                          'url' => reference['data_url'] || reference['url']
                        }
                      else
                        { 'url' => reference.to_s }
                      end
            path = ensure_local_image(payload, folder: 'inspiration_refs', prefix: format('ref-%02d', index + 1))
            saved << {
              'index' => index + 1,
              'name' => reference.is_a?(Hash) ? reference['name'].to_s : '',
              'path' => path,
              'url' => file_url(path)
            }
          rescue StandardError => e
            saved << {
              'index' => index + 1,
              'name' => reference.is_a?(Hash) ? reference['name'].to_s : '',
              'error' => e.message
            }
          end
        end
        saved
      end

      def fetch_online_pinterest_references(plan:, count:, progress:, base_image_path: nil, use_lens: false)
        queries = Array(plan['pinterest_queries']).first(count)
        lens_urls = []
        if use_lens && File.file?(base_image_path.to_s)
          emit_progress(
            progress,
            stage: 'pinterest_lens',
            message: '正在把白模截图发送到 Pinterest Lens，增强结构相似灵感召回...',
            target_count: count
          )
          lens_urls = pinterest_lens_image_urls(base_image_path.to_s, count: [count * 4, 12].max)
          emit_progress(
            progress,
            stage: 'pinterest_lens',
            message: lens_urls.empty? ? 'Pinterest Lens 未返回可用图片，继续使用文字搜索。' : "Pinterest Lens 返回 #{lens_urls.length} 张候选图，将与文字搜索结果合并。",
            target_count: count,
            lens_count: lens_urls.length
          )
        elsif use_lens
          emit_progress(
            progress,
            stage: 'pinterest_lens',
            message: '未找到可上传的白模截图，已跳过 Pinterest Lens 增强。',
            target_count: count
          )
        end

        references = []
        used_remote_urls = {}
        count.times do |offset|
          query_item = queries[offset].is_a?(Hash) ? queries[offset] : {}
          index = positive_int(query_item['index'], offset + 1)
          query = query_item['query'].to_s.strip
          query = "interior design inspiration #{index}" if query.empty?
          search_url = query_item['search_url'].to_s
          search_url = pinterest_search_url(query) if search_url.empty?
          emit_progress(
            progress,
            stage: 'pinterest_fetch',
            message: "正在在线获取 Pinterest 灵感图 #{offset + 1}/#{count}...",
            index: offset + 1,
            target_count: count,
            query: query,
            search_url: search_url
          )

          references << fetch_one_pinterest_reference(
            index: index,
            query: query,
            search_url: search_url,
            intent: query_item['intent'].to_s,
            lens_candidate_urls: lens_candidates_for_index(lens_urls, offset),
            used_remote_urls: used_remote_urls
          )
        end
        references
      end

      def lens_candidates_for_index(lens_urls, offset)
        urls = Array(lens_urls)
        return [] if urls.empty?

        primary = urls.drop(offset).first(8)
        (primary + urls.first(8)).uniq
      end

      def fetch_one_pinterest_reference(index:, query:, search_url:, intent:, lens_candidate_urls: [], used_remote_urls: {})
        lens_candidate_urls = Array(lens_candidate_urls).map(&:to_s).reject(&:empty?).uniq
        lens_url_lookup = lens_candidate_urls.each_with_object({}) { |url, hash| hash[url] = true }
        urls = (lens_candidate_urls + pinterest_image_urls(query)).uniq
        raise 'Pinterest 搜索页没有向当前工具请求暴露可下载的 pin 图片。' if urls.empty?

        last_error = nil
        urls.first(12).each do |remote_url|
          begin
            next if used_remote_urls[remote_url]

            path = download_remote_image(
              remote_url,
              folder: 'inspiration_refs',
              prefix: format('pinterest-%02d', index),
              headers: pinterest_headers(referer: search_url)
            )
            next if File.size(path) < 8_000

            used_remote_urls[remote_url] = true
            return {
              'index' => index,
              'name' => "Pinterest 灵感 #{index}",
              'query' => query,
              'intent' => intent,
              'search_url' => search_url,
              'remote_url' => remote_url,
              'source_kind' => lens_url_lookup[remote_url] ? 'pinterest_lens' : 'pinterest_text',
              'path' => path,
              'url' => file_url(path)
            }
          rescue StandardError => e
            last_error = e
          end
        end

        raise(last_error || RuntimeError.new('Pinterest 图片候选下载失败。'))
      rescue StandardError => e
        {
          'index' => index,
          'name' => "Pinterest 灵感 #{index}",
          'query' => query,
          'intent' => intent,
          'search_url' => search_url,
          'remote_url' => (defined?(urls) && urls.first ? urls.first.to_s : ''),
          'source_kind' => 'pinterest_search',
          'path' => '',
          'url' => (defined?(urls) && urls.first ? urls.first.to_s : ''),
          'error' => e.message
        }
      end

      def enrich_pinterest_references(client:, base_image_path:, references:, plan:, progress:, settings: {})
        plan_error = plan.is_a?(Hash) ? plan['error'].to_s.strip : ''
        unless plan_error.empty?
          friendly_error = user_facing_ai_error(plan_error)
          emit_progress(
            progress,
            stage: 'reference_fallback',
            message: "多模态文本链路本轮不可用，已跳过逐图反推，改用备用提示词继续生成：#{friendly_error}"
          )
          return Array(references).map do |reference|
            next reference unless reference.is_a?(Hash)

            index = positive_int(reference['index'], 1)
            version = plan_item(plan['versions'], index)
            fallback_text = version['render_prompt'].to_s.empty? ? version['style_summary'].to_s : version['render_prompt'].to_s
            reference.merge(
              'analysis' => normalize_reference_analysis(
                {},
                fallback_text: fallback_text
              ).merge('error' => friendly_error, 'raw_error' => plan_error)
            )
          end
        end

        valid_references = Array(references).select do |reference|
          reference.is_a?(Hash) && !reference['path'].to_s.empty? && File.file?(reference['path'].to_s)
        end

        return references if valid_references.empty?

        emit_progress(
          progress,
          stage: 'reference_analyzing',
          message: "正在批量提取 #{valid_references.length} 张 Pinterest 灵感图的提示词和标注点...",
          target_count: Array(references).length
        )

        routes = text_request_routes(
          settings,
          primary_key: 'reference_model',
          default_model: plan['analysis_model'].to_s.empty? ? 'gpt-5.5' : plan['analysis_model'].to_s
        )
        analyses = {}
        batch_error = nil
        begin
          valid_references.each_slice(4).with_index do |batch_references, batch_index|
            emit_progress(
              progress,
              stage: 'reference_analyzing',
              message: "正在用 #{routes.first[:label]} / #{routes.first[:model]} 批量提取 Pinterest 灵感图 #{batch_index * 4 + 1}-#{batch_index * 4 + batch_references.length}/#{valid_references.length}...",
              target_count: Array(references).length
            )
            batch = nil
            used_model = nil
            model_errors = []
            routes.each do |route|
              text_model = route[:model]
              route_client = route[:primary] ? client : ApiClient.new(route[:settings])
              begin
                batch = route_client.inspiration_reference_batch_analysis(
                  base_image_path: base_image_path,
                  references: batch_references,
                  plan: plan,
                  text_model: text_model,
                  include_images: true
                )
                used_model = "#{route[:label]} / #{text_model}"
                break
              rescue StandardError => e
                model_errors << "#{route[:label]} #{text_model}: #{e.message}"
                next unless planner_image_fallback_error?(e)

                begin
                  batch = route_client.inspiration_reference_batch_analysis(
                    base_image_path: base_image_path,
                    references: batch_references,
                    plan: plan,
                    text_model: text_model,
                    include_images: false
                  )
                  used_model = "#{route[:label]} / #{text_model} text-only"
                  break
                rescue StandardError => text_error
                  model_errors << "#{route[:label]} #{text_model} text-only: #{text_error.message}"
                end
              end
            end
            raise(model_errors.join(' | ')) unless batch

            raw_analyses = batch['analyses'].is_a?(Array) ? batch['analyses'] : batch['references']
            Array(raw_analyses).each do |item|
              next unless item.is_a?(Hash)

              item['analysis_model'] = used_model
              analyses[item['index'].to_i] = item
            end
          end
        rescue StandardError => e
          batch_error = e
          emit_progress(
            progress,
            stage: 'reference_fallback',
            message: "批量反推灵感图较慢或失败，已改用搜索词和版本方向继续生成：#{user_facing_ai_error(e)}"
          )
        end

        Array(references).map do |reference|
          next reference unless reference.is_a?(Hash)

          index = positive_int(reference['index'], 1)
          version = plan_item(plan['versions'], index)
          fallback_text = version['render_prompt'].to_s.empty? ? version['style_summary'].to_s : version['render_prompt'].to_s
          analysis = normalize_reference_analysis(
            analyses[index] || {},
            fallback_text: fallback_text
          )
          if batch_error && analyses[index].nil?
            analysis['error'] = user_facing_ai_error(batch_error)
            analysis['raw_error'] = batch_error.message
          end
          reference.merge('analysis' => analysis)
        end
      end

      def pinterest_image_urls(query, open_timeout: nil, read_timeout: nil)
        worker_urls = pinterest_worker_image_urls(query, count: 24)
        return worker_urls unless worker_urls.empty?

        uri = URI(pinterest_search_url(query))
        response = http_get_follow(uri, headers: pinterest_headers, open_timeout: open_timeout, read_timeout: read_timeout)
        unless response.is_a?(Net::HTTPSuccess)
          raise "Pinterest search failed: HTTP #{response.code}"
        end

        text = response.body.to_s
        text = CGI.unescapeHTML(text)
        3.times do
          text = text
                 .gsub('\\u002F', '/')
                 .gsub('\\/', '/')
                 .gsub('%2F', '/')
                 .gsub('%3A', ':')
        end

        patterns = [
          %r{https?:/+i\.pinimg\.com/[^"' <>\s)\\]+\.(?:jpg|jpeg|png|webp)}i,
          %r{//i\.pinimg\.com/[^"' <>\s)\\]+\.(?:jpg|jpeg|png|webp)}i,
          %r{i\.pinimg\.com/[^"' <>\s)\\]+\.(?:jpg|jpeg|png|webp)}i
        ]
        urls = []
        patterns.each do |pattern|
          text.to_enum(:scan, pattern).each do
            match = Regexp.last_match
            raw = match[0].to_s
            start = [match.begin(0) - 160, 0].max
            context = text[start, 320].to_s.downcase
            next if context.include?('iconbuttonsocial') || context.include?('instagram-background')

            url = raw
            url = "https:#{url}" if url.start_with?('//')
            url = "https://#{url}" if url.start_with?('i.pinimg.com')
            url = url.sub(%r{\?.*\z}, '')
            next unless url =~ /\.(jpg|jpeg|png|webp)\z/i

            urls << normalize_pinimg_url(url)
          end
        end
        urls.uniq
      end

      def pinterest_worker_image_urls(query, count:)
        return [] unless start_pinterest_worker

        uri = URI("#{pinterest_worker_base_url}/search?#{URI.encode_www_form(q: query.to_s, count: count.to_i)}")
        response = http_get_follow(uri, headers: {}, open_timeout: 2, read_timeout: 80)
        return [] unless response.is_a?(Net::HTTPSuccess)

        json = JSON.parse(response.body.to_s)
        Array(json['urls']).map do |url|
          normalize_pinimg_url(url.to_s.sub(%r{\?.*\z}, ''))
        end.select do |url|
          url =~ %r{\Ahttps://i\.pinimg\.com/.+\.(jpg|jpeg|png|webp)\z}i
        end.uniq
      rescue StandardError
        []
      end

      def pinterest_lens_image_urls(image_path, count:)
        return [] unless File.file?(image_path.to_s)
        return [] unless start_pinterest_worker

        uri = URI("#{pinterest_worker_base_url}/lens-search")
        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request.body = JSON.generate(
          image_path: image_path.to_s,
          count: count.to_i
        )
        http = Net::HTTP.new(uri.host, uri.port, nil)
        http.open_timeout = 3
        http.read_timeout = 120
        response = http.request(request)
        return [] unless response.is_a?(Net::HTTPSuccess)

        json = JSON.parse(response.body.to_s)
        Array(json['urls']).map do |url|
          normalize_pinimg_url(url.to_s.sub(%r{\?.*\z}, ''))
        end.select do |url|
          url =~ %r{\Ahttps://i\.pinimg\.com/.+\.(jpg|jpeg|png|webp)\z}i
        end.uniq
      rescue StandardError => e
        warn "Pinterest Lens failed: #{e.message}" if $DEBUG
        []
      end

      def start_pinterest_worker
        return true if pinterest_worker_ready?

        stop_stale_pinterest_worker if pinterest_worker_status
        script = File.join(PLUGIN_DIR, 'pinterest_worker.js')
        return false unless File.file?(script)

        log_path = File.join(default_output_dir, 'pinterest_worker.log')
        FileUtils.mkdir_p(File.dirname(log_path))
        pid = Process.spawn(
          node_command,
          script,
          '--port',
          PINTEREST_WORKER_PORT.to_s,
          '--debug-port',
          PINTEREST_WORKER_DEBUG_PORT.to_s,
          out: log_path,
          err: [:child, :out]
        )
        Process.detach(pid)
        started = Time.now
        until Time.now - started > 8
          return true if pinterest_worker_ready?

          sleep 0.25
        end
        false
      rescue StandardError
        false
      end

      def pinterest_worker_ready?
        status = pinterest_worker_status
        status && status['worker_version'].to_s == PINTEREST_WORKER_VERSION
      rescue StandardError
        false
      end

      def pinterest_worker_status
        response = http_get_follow(URI("#{pinterest_worker_base_url}/status"), headers: {}, open_timeout: 1, read_timeout: 2)
        return nil unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body.to_s)
      rescue StandardError
        nil
      end

      def stop_stale_pinterest_worker
        command = <<~POWERSHELL
          $connections = Get-NetTCPConnection -LocalPort #{PINTEREST_WORKER_PORT} -State Listen -ErrorAction SilentlyContinue
          if ($connections) {
            $connections | Select-Object -ExpandProperty OwningProcess -Unique | ForEach-Object {
              Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue
            }
          }
        POWERSHELL
        system('powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', command)
        sleep 1
      rescue StandardError
        nil
      end

      def node_command
        candidates = [
          ENV['LOCAL_AI_RENDER_NODE'],
          'node',
          File.join(ENV['PROGRAMFILES'].to_s, 'nodejs', 'node.exe'),
          File.join(ENV['PROGRAMFILES(X86)'].to_s, 'nodejs', 'node.exe')
        ].compact.reject(&:empty?)
        candidates.find { |candidate| candidate == 'node' || File.file?(candidate) } || 'node'
      end

      def normalize_pinimg_url(url)
        value = url.to_s
        value = value.sub(%r{/\d+x/}, '/736x/')
        value
      end

      def pinterest_headers(referer: 'https://www.pinterest.com/')
        {
          'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/125 Safari/537.36',
          'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
          'Accept-Language' => 'en-US,en;q=0.9,zh-CN;q=0.8',
          'Referer' => referer.to_s.empty? ? 'https://www.pinterest.com/' : referer.to_s
        }
      end

      def build_inspiration_plan(client:, image_path:, base_note:, count:, references:, settings: {})
        errors = []
        text_request_routes(settings, primary_key: 'planner_model', default_model: 'gpt-5.5').each do |route|
          text_model = route[:model]
          route_client = route[:primary] ? client : ApiClient.new(route[:settings])
          begin
            plan = route_client.inspiration_plan(
              image_path: image_path,
              note: base_note,
              count: count,
              references: references,
              text_model: text_model,
              include_images: true
            )
            return normalize_inspiration_plan(plan, base_note: base_note, count: count).merge(
              'analysis_model' => text_model,
              'analysis_channel' => route[:label],
              'analysis_mode' => 'vision'
            )
          rescue StandardError => e
            errors << "#{route[:label]} #{text_model}: #{e.message}"
            next unless planner_image_fallback_error?(e)

            begin
              plan = route_client.inspiration_plan(
                image_path: image_path,
                note: base_note,
                count: count,
                references: references,
                text_model: text_model,
                include_images: false
              )
              return normalize_inspiration_plan(plan, base_note: base_note, count: count).merge(
                'analysis_model' => text_model,
                'analysis_channel' => route[:label],
                'analysis_mode' => 'text_only',
                'notice' => '当前文本模型不支持直接读取白模截图，已改用文本规划继续；最终渲染仍以原始白模截图作为基础图。'
              )
            rescue StandardError => text_error
              errors << "#{route[:label]} #{text_model} text-only: #{text_error.message}"
            end
          end
        end
        fallback_inspiration_plan(base_note: base_note, count: count, error: errors.join(' | '))
      end

      def planner_image_fallback_error?(error)
        message = "#{error.class.name} #{error.message}"
        message.match?(/Not supported model|Param Incorrect|unsupported|not support|image_url|input_image|vision|multimodal|multi-modal|HTTP 400|HTTP 413|HTTP 415|HTTP 422|ReadTimeout|Timeout|execution expired/i)
      end

      def text_model_candidates(settings, primary_key:, default_model:)
        settings = {} unless settings.is_a?(Hash)
        raw = []
        raw << settings[primary_key].to_s
        raw.concat(settings['backup_text_models'].to_s.split(/[,，\s]+/))
        raw << default_model.to_s
        raw.map(&:strip).reject(&:empty?).uniq
      end

      def text_request_routes(settings, primary_key:, default_model:)
        settings = {} unless settings.is_a?(Hash)
        models = text_model_candidates(settings, primary_key: primary_key, default_model: default_model)
        routes = []
        routes << {
          primary: true,
          label: endpoint_label(settings['text_endpoint'].to_s.empty? ? settings['endpoint'] : settings['text_endpoint'], fallback: '主分析接口'),
          settings: settings,
          models: models
        }

        endpoints = split_setting_list(settings['backup_text_endpoints'])
        keys = split_setting_list(settings['backup_text_api_keys'], keep_empty: true)
        endpoints.each_with_index do |endpoint, index|
          next if endpoint.empty?

          route_settings = settings.dup
          route_settings['text_endpoint'] = endpoint
          route_settings['text_api_key'] = keys[index].to_s.empty? ? settings['text_api_key'].to_s : keys[index].to_s
          routes << {
            primary: false,
            label: endpoint_label(endpoint, fallback: "备用分析接口#{index + 1}"),
            settings: route_settings,
            models: models
          }
        end

        seen = {}
        routes.flat_map do |route|
          route[:models].map do |model|
            key = [
              route[:settings]['text_endpoint'].to_s,
              route[:settings]['text_api_key'].to_s.empty? ? route[:settings]['api_key'].to_s : route[:settings]['text_api_key'].to_s,
              model
            ].join("\u0000")
            next if seen[key]

            seen[key] = true
            {
              primary: route[:primary],
              label: route[:label],
              settings: route[:settings],
              model: model
            }
          end
        end.compact
      end

      def split_setting_list(value, keep_empty: false)
        items = value.to_s.split(/[\r\n,，]+/).map(&:strip)
        keep_empty ? items : items.reject(&:empty?)
      end

      def endpoint_label(endpoint, fallback:)
        value = endpoint.to_s.strip
        return fallback if value.empty?

        uri = URI(value)
        host = uri.host.to_s
        host.empty? ? fallback : host
      rescue StandardError
        fallback
      end

      def normalize_inspiration_plan(plan, base_note:, count:)
        data = plan.is_a?(Hash) ? plan : {}
        data['model_summary'] = data['model_summary'].to_s.strip
        data['model_summary'] = '未能获得稳定的白模总结，使用用户灵感说明和固定空间保持约束继续生成。' if data['model_summary'].empty?
        queries = Array(data['pinterest_queries']).map.with_index do |item, index|
          item = { 'query' => item.to_s } unless item.is_a?(Hash)
          query = item['query'].to_s.strip
          query = "#{base_note} interior design inspiration" if query.empty?
          {
            'index' => index + 1,
            'query' => query,
            'intent' => item['intent'].to_s,
            'search_url' => pinterest_search_url(query)
          }
        end
        versions = Array(data['versions']).map.with_index do |item, index|
          item = { 'style_summary' => item.to_s } unless item.is_a?(Hash)
          style = item['style_summary'].to_s.strip
          style = item['render_prompt'].to_s.strip if style.empty?
          style = inspiration_style(index + 1) if style.empty?
          render_prompt = item['render_prompt'].to_s.strip.empty? ? style : item['render_prompt'].to_s.strip
          {
            'index' => index + 1,
            'title' => item['title'].to_s.strip.empty? ? "版本 #{index + 1}" : item['title'].to_s.strip,
            'style_summary' => style,
            'render_prompt' => render_prompt,
            'key_points' => normalize_key_points(item['key_points'], render_prompt)
          }
        end

        while queries.length < count
          index = queries.length + 1
          query = "#{base_note} #{inspiration_style(index)} interior design Pinterest"
          queries << {
            'index' => index,
            'query' => query,
            'intent' => inspiration_style(index),
            'search_url' => pinterest_search_url(query)
          }
        end

        while versions.length < count
          index = versions.length + 1
          style = inspiration_style(index)
          versions << {
            'index' => index,
            'title' => "版本 #{index}",
            'style_summary' => style,
            'render_prompt' => style,
            'key_points' => normalize_key_points([], style)
          }
        end

        {
          'model_summary' => data['model_summary'],
          'pinterest_queries' => queries.first(count),
          'versions' => versions.first(count),
          'raw' => data
        }
      end

      def fallback_inspiration_plan(base_note:, count:, error: nil)
        queries = count.times.map do |index|
          version = index + 1
          query = "#{base_note} #{inspiration_style(version)} interior design Pinterest"
          {
            'index' => version,
            'query' => query,
            'intent' => inspiration_style(version),
            'search_url' => pinterest_search_url(query)
          }
        end
        versions = count.times.map do |index|
          version = index + 1
          style = inspiration_style(version)
          {
            'index' => version,
            'title' => "版本 #{version}",
            'style_summary' => style,
            'render_prompt' => style,
            'key_points' => normalize_key_points([], style)
          }
        end
        {
          'model_summary' => '白模视觉总结暂不可用，已根据项目说明和固定结构约束继续生成灵感方向；最终渲染仍以原始白模截图作为基础图。',
          'pinterest_queries' => queries,
          'versions' => versions,
          'notice' => user_facing_ai_error(error),
          'error' => error.to_s
        }
      end

      def user_facing_ai_error(error)
        message = error.respond_to?(:message) ? error.message.to_s : error.to_s
        return '模型链路暂时不可用，已启用备用连续流程。' if message.empty?

        return '当前文本模型不支持图片输入，已自动改用文本规划。' if message =~ /Not supported model|Param Incorrect|unsupported|not support|image_url|input_image|vision|multimodal|multi-modal|HTTP 400|HTTP 415|HTTP 422/i
        return '接口网络波动或响应超时，已保存进度并继续可恢复流程。' if message =~ /OpenTimeout|ReadTimeout|Timeout|execution expired|Failed to open TCP|network|temporar|HTTP 408|HTTP 429|HTTP 5\d\d/i
        return '接口鉴权或额度异常，请检查当前密钥和模型权限。' if message =~ /HTTP 401|HTTP 403|unauthori|forbidden|quota|insufficient/i

        '模型链路本轮返回异常，已启用备用连续流程。'
      end

      def pinterest_search_url(query)
        "https://www.pinterest.com/search/pins/?q=#{URI.encode_www_form_component(query.to_s)}"
      end

      def emit_progress(progress, payload)
        progress.call({ ok: true }.merge(payload)) if progress
      rescue StandardError
        nil
      end

      def plan_item(items, index)
        Array(items).find { |item| item.is_a?(Hash) && item['index'].to_i == index } || {}
      end

      def normalize_reference_analysis(analysis, fallback_text:)
        data = analysis.is_a?(Hash) ? analysis : {}
        prompt = data['extracted_prompt'].to_s.strip
        prompt = fallback_text.to_s.strip if prompt.empty?
        summary = data['summary'].to_s.strip
        summary = prompt if summary.empty?
        {
          'summary' => summary,
          'extracted_prompt' => prompt,
          'key_points' => normalize_key_points(data['key_points'], prompt)
        }
      end

      def normalize_key_points(points, fallback_text)
        defaults = [
          ['材质肌理', 24, 28],
          ['灯光层次', 68, 30],
          ['配色氛围', 35, 70],
          ['软装陈列', 74, 68]
        ]
        raw = Array(points).first(4)
        raw = defaults.map { |label, x, y| { 'label' => label, 'detail' => fallback_text.to_s, 'x' => x, 'y' => y } } if raw.empty?
        raw.map.with_index do |item, index|
          item = { 'label' => item.to_s, 'detail' => fallback_text.to_s } unless item.is_a?(Hash)
          default = defaults[index] || defaults.last
          label = item['label'].to_s.strip
          label = default[0] if label.empty?
          detail = item['detail'].to_s.strip
          detail = item['summary'].to_s.strip if detail.empty?
          detail = fallback_text.to_s.strip if detail.empty?
          {
            'label' => label[0, 18],
            'detail' => detail,
            'x' => bounded_percent(item['x'], default[1]),
            'y' => bounded_percent(item['y'], default[2])
          }
        end
      end

      def bounded_percent(value, fallback)
        parsed = Float(value)
        [[parsed, 5.0].max, 95.0].min.round
      rescue StandardError
        fallback
      end

      def inspiration_source(index:, references:, plan:)
        query = plan_item(plan['pinterest_queries'], index)
        version = plan_item(plan['versions'], index)
        ref = Array(references).find { |item| item.is_a?(Hash) && item['index'].to_i == index }
        has_image = ref && !ref['path'].to_s.empty?
        remote_image_url = ref ? ref['url'].to_s : ''
        remote_image_url = ref['remote_url'].to_s if ref && remote_image_url.empty?
        has_remote_image = !remote_image_url.empty?
        analysis = ref && ref['analysis'].is_a?(Hash) ? ref['analysis'] : {}
        extracted_prompt = analysis['extracted_prompt'].to_s.strip
        extracted_prompt = version['render_prompt'].to_s.strip if extracted_prompt.empty?
        extracted_prompt = version['style_summary'].to_s.strip if extracted_prompt.empty?
        summary = analysis['summary'].to_s.strip
        summary = version['style_summary'].to_s.strip if summary.empty?
        source_kind = ref ? ref['source_kind'].to_s : ''
        source_type = if source_kind == 'pinterest_lens'
                        'pinterest_lens'
                      elsif has_image
                        'pinterest_online'
                      elsif has_remote_image
                        'pinterest_remote'
                      elsif ref
                        'pinterest_fetch_failed'
                      else
                        'pinterest_search'
                      end
        key_points = normalize_key_points(
          analysis['key_points'].is_a?(Array) && !analysis['key_points'].empty? ? analysis['key_points'] : version['key_points'],
          extracted_prompt
        )
        {
          'index' => index,
          'type' => source_type,
          'source_kind' => source_kind,
          'title' => version['title'].to_s.empty? ? "灵感 #{index}" : version['title'].to_s,
          'summary' => summary,
          'extracted_prompt' => extracted_prompt,
          'render_prompt' => version['render_prompt'].to_s,
          'key_points' => key_points,
          'query' => ref ? ref['query'].to_s : query['query'].to_s,
          'intent' => ref ? ref['intent'].to_s : query['intent'].to_s,
          'search_url' => ref ? ref['search_url'].to_s : query['search_url'].to_s,
          'remote_url' => ref ? ref['remote_url'].to_s : '',
          'reference_name' => ref ? ref['name'].to_s : '',
          'image_path' => has_image ? ref['path'].to_s : '',
          'image_url' => has_image ? ref['url'].to_s : remote_image_url,
          'fetch_error' => ref ? ref['error'].to_s : '',
          'analysis_error' => analysis['error'].to_s
        }
      end

      def upsert_inspiration_result(results, item)
        index = (item[:index] || item['index']).to_i
        existing_index = results.index do |record|
          (record[:index] || record['index']).to_i == index
        end
        if existing_index
          results[existing_index] = item
        else
          results << item
        end
        results.sort_by! { |record| (record[:index] || record['index']).to_i }
        results
      end

      def ensure_render_api_ready(client:, progress:, target_count:)
        3.times do |attempt|
          begin
            result = client.test_connection
            emit_progress(
              progress,
              stage: 'render_preflight',
              message: "渲染接口预检通过：#{result[:message] || result['message'] || 'API 可访问'}",
              target_count: target_count
            )
            return true
          rescue StandardError => e
            if attempt < 2
              delay = [2, 6, 12][attempt]
              emit_progress(
                progress,
                stage: 'render_preflight',
                message: "渲染接口预检遇到网络波动，#{delay} 秒后重试：#{e.message.to_s[0, 140]}",
                target_count: target_count,
                error: e.message,
                error_class: e.class.name
              )
              sleep delay
            else
              emit_progress(
                progress,
                stage: 'render_preflight',
                message: "渲染接口预检仍不稳定，将降为单线程并依靠单张重试继续：#{e.message.to_s[0, 140]}",
                target_count: target_count,
                error: e.message,
                error_class: e.class.name
              )
            end
          end
        end
        false
      end

      def render_inspiration_version(client:, prompt:, image_path:, camera:, options:, version:, count:, progress:)
        attempts = 0

        begin
          attempts += 1
          client.render(
            prompt: prompt,
            image_path: image_path,
            camera: camera,
            options: options
          )
        rescue StandardError => e
          retryable = retryable_render_error?(e)
          max_attempts = retryable ? 4 : 2
          raise if attempts >= max_attempts

          emit_progress(
            progress,
            stage: 'render_retry',
            message: "第 #{version}/#{count} 个版本#{retryable ? '遇到网络波动' : '生成失败'}，正在第 #{attempts + 1}/#{max_attempts} 次重试：#{e.message.to_s[0, 140]}",
            index: version,
            target_count: count,
            error: e.message,
            error_class: e.class.name
          )
          sleep(retry_delay_seconds(attempts, retryable))
          retry
        end
      end

      def retryable_render_error?(error)
        message = "#{error.class.name} #{error.message}"
        message.match?(/网络连接失败|OpenTimeout|ReadTimeout|Timeout|execution expired|temporar|HTTP 408|HTTP 409|HTTP 425|HTTP 429|HTTP 5\d\d/i)
      end

      def retry_delay_seconds(attempts, retryable)
        return 2 unless retryable

        [3, 8, 18][attempts - 1] || 18
      end

      def inspiration_version_prompt(base_note:, index:, total:, references:, plan: nil)
        matching_reference = references.find { |item| item.is_a?(Hash) && item['index'].to_i == index && item['path'].to_s != '' }
        reference_lines = [matching_reference].compact.map do |item|
          label = item['name'].to_s.empty? ? "参考图#{item['index']}" : item['name'].to_s
          analysis = item['analysis'].is_a?(Hash) ? item['analysis'] : {}
          note = analysis['extracted_prompt'].to_s.strip
          note = analysis['summary'].to_s.strip if note.empty?
          note = item['intent'].to_s.strip if note.empty?
          "- #{label}: #{File.basename(item['path'].to_s)}；#{note}"
        end
        reference_text = reference_lines.empty? ? '无额外参考图，仅根据灵感说明和白模空间生成。' : reference_lines.join("\n")
        plan ||= {}
        version = plan_item(plan['versions'], index)
        query = plan_item(plan['pinterest_queries'], index)
        model_summary = plan['model_summary'].to_s.strip
        reference = references.find { |item| item.is_a?(Hash) && item['index'].to_i == index }
        analysis = reference && reference['analysis'].is_a?(Hash) ? reference['analysis'] : {}
        version_prompt = version['render_prompt'].to_s.strip
        version_prompt = analysis['extracted_prompt'].to_s.strip unless analysis['extracted_prompt'].to_s.strip.empty?
        version_prompt = version['style_summary'].to_s.strip if version_prompt.empty?
        version_prompt = inspiration_style(index) if version_prompt.empty?

        <<~PROMPT
          以附加的 SketchUp 白模截图作为唯一空间基础图，生成第 #{index}/#{total} 版客户提案效果图。
          必须保持原相机视角、空间比例、墙体、开口、柱网、楼梯、固定构件、主要体块关系和动线不变。
          不要改变白模的建筑结构，不要新增错误墙体、门洞、柱子或遮挡视线的大型物件。
          只改变材质、灯光、色彩、软装、陈列、绿植、装饰、可替换家具表皮和整体氛围。
          多模态模型对白模空间的总结：#{model_summary}
          灵感方向：#{base_note}
          Pinterest 搜索词：#{query['query']}
          Pinterest 反推灵感：#{query['intent']}
          Pinterest/参考图线索：
          #{reference_text}
          本版本方向：#{version_prompt}
          输出写实建筑/室内摄影级效果图，真实材质纹理，干净构图，完整保留原白模视角。
          Negative prompt: changed layout, moved openings, extra columns, wrong perspective, distorted geometry, unreadable structure, logo, watermark, text, people blocking view, low quality.
        PROMPT
      end

      def inspiration_style(index)
        styles = [
          '温暖木色、奶油白墙面、午后自然光，适合亲和型住宅或接待空间。',
          '微水泥、深色金属、线性灯光，强调现代商业质感和利落体块。',
          '酒店式浅石材、暖灰织物、隐藏灯带，营造高级但克制的提案氛围。',
          '侘寂自然感，粗粝肌理、低饱和色、柔和漫射光，突出空间安静感。',
          '黑白灰极简，局部木饰面和艺术灯具，强调结构线条和秩序。',
          '轻奢石材、香槟金属、精致软装，适合高端客户汇报版本。',
          '日式原木、纸感灯光、浅色织物，营造清爽、放松、细腻的尺度。',
          '艺术展厅气质，大面积留白、重点照明、雕塑感家具，突出空间展示性。',
          '精品零售氛围，局部重点照明、展示台、品牌感陈列，但不生成文字或 logo。',
          '自然度假风，藤编、浅木、绿植、阳光和通透材质，增强亲近自然感。',
          '未来科技感，哑光金属、发光线条、冷暖对比灯光，保持真实可落地。',
          '北欧生活感，浅木地板、白墙、柔软织物、自然光和干净收纳。'
        ]
        styles[(index - 1) % styles.length]
      end

      def ensure_local_image(payload, folder:, prefix:)
        path = payload['path'].to_s
        return copy_image(path, folder: folder, prefix: prefix) if File.file?(path)

        url = payload['url'].to_s
        file_path = file_url_to_path(url)
        return copy_image(file_path, folder: folder, prefix: prefix) if file_path && File.file?(file_path)

        if url.start_with?('data:image/')
          return save_data_url_image(url, folder: folder, prefix: prefix)
        end

        if url =~ %r{\Ahttps?://}i
          return download_remote_image(url, folder: folder, prefix: prefix)
        end

        raise ArgumentError, 'No reusable result image was found.'
      end

      def copy_image(path, folder:, prefix:)
        ext = File.extname(path)
        ext = '.png' if ext.empty?
        dir = File.join(output_root, folder)
        FileUtils.mkdir_p(dir)
        dest = File.join(dir, "#{prefix}-#{timestamp}#{ext}")
        if File.expand_path(path) == File.expand_path(dest)
          path
        else
          FileUtils.cp(path, dest)
          dest
        end
      end

      def persist_result(result, payload, action:, settings: nil)
        image_payload = result_image_payload(result)
        return result if image_payload['path'].empty? && image_payload['url'].empty?

        local_path = ensure_local_image(image_payload, folder: 'history_images', prefix: action)
        settings ||= Settings.to_h
        record = {
          'id' => "#{Time.now.to_i}-#{rand(1_000_000)}",
          'created_at' => Time.now.strftime('%Y-%m-%d %H:%M:%S'),
          'action' => action,
          'mode' => settings['request_mode'],
          'model' => settings['model'],
          'prompt' => payload['prompt'].to_s,
          'source_path' => payload['image_path'].to_s,
          'path' => local_path,
          'url' => file_url(local_path)
        }
        history_error = nil
        unless inspiration_history_action?(action)
          begin
            history_mutex.synchronize do
              records = [record] + history_records
              write_history(records.first(50))
            end
          rescue StandardError => e
            history_error = e
          end
        end

        additions = {
          image_path: local_path,
          image_url: file_url(local_path),
          history_record: record
        }
        additions[:history_error] = history_error.message if history_error
        merge_result(result, additions)
      end

      def result_image_payload(result)
        path = result[:image_path] || result['image_path'] || result[:path] || result['path']
        url = result[:image_url] || result['image_url'] || result[:url] || result['url']
        { 'path' => path.to_s, 'url' => url.to_s }
      end

      def merge_result(result, additions)
        base = result.dup
        additions.each { |key, value| base[key] = value }
        base
      end

      def history_path
        File.join(output_root, 'history.json')
      end

      def inspiration_run_path(run_id)
        File.join(output_root, 'inspiration_runs', "#{run_id}.json")
      end

      def latest_inspiration_run_file
        dir = File.join(output_root, 'inspiration_runs')
        return nil unless Dir.exist?(dir)

        files = Dir.glob(File.join(dir, 'inspiration-*.json')).select { |path| File.file?(path) }
        return nil if files.empty?

        incomplete = files.select do |path|
          data = JSON.parse(File.read(path, encoding: 'UTF-8'))
          !data['complete'] || Array(data['results']).count { |item| item.is_a?(Hash) && item['ok'] } < data['target_count'].to_i
        rescue StandardError
          false
        end
        (incomplete.empty? ? files : incomplete).max_by { |path| File.mtime(path) }
      end

      def persist_inspiration_run_state(run_id, target_count:, base_image_path:, plan:, references:, results:, complete: false)
        path = inspiration_run_path(run_id)
        run_state_mutex.synchronize do
          FileUtils.mkdir_p(File.dirname(path))
          payload = {
            ok: true,
            run_id: run_id,
            updated_at: Time.now.strftime('%Y-%m-%d %H:%M:%S'),
            complete: complete,
            target_count: target_count,
            generated_count: Array(results).count { |item| item[:ok] || item['ok'] },
            failed_count: Array(results).count { |item| (item.key?(:ok) ? item[:ok] : item['ok']) == false },
            pending_count: Array(results).count { |item| item[:pending] || item['pending'] || item[:status] == 'rendering' || item['status'] == 'rendering' },
            base_image: {
              path: base_image_path.to_s,
              url: file_url(base_image_path.to_s)
            },
            plan: plan,
            references: references,
            results: results
          }
          File.write(path, JSON.pretty_generate(payload), encoding: 'UTF-8')
        end
        path
      rescue StandardError
        nil
      end

      def inspiration_history_records
        dir = File.join(output_root, 'inspiration_runs')
        return [] unless Dir.exist?(dir)

        Dir.glob(File.join(dir, 'inspiration-*.json')).filter_map do |path|
          inspiration_history_record(path)
        end.sort_by { |record| record['updated_at'].to_s }.reverse.first(50)
      rescue StandardError
        []
      end

      def inspiration_history_record(path)
        data = JSON.parse(File.read(path, encoding: 'UTF-8'))
        return nil unless data.is_a?(Hash)

        run_id = data['run_id'].to_s
        run_id = File.basename(path, '.json') if run_id.empty?
        results = Array(data['results']).select { |item| item.is_a?(Hash) }.map { |item| normalize_result_urls(item) }
        references = Array(data['references']).select { |item| item.is_a?(Hash) }.map { |item| normalize_result_urls(item) }
        base_image = data['base_image'].is_a?(Hash) ? normalize_result_urls(data['base_image']) : {}
        target_count = positive_int(data['target_count'], results.length)
        generated_count = positive_int(data['generated_count'], results.count { |item| item['ok'] })
        failed_count = positive_int(data['failed_count'], results.count { |item| item['ok'] == false })
        thumbnail = results.find { |item| item['ok'] && !item['image_url'].to_s.empty? } ||
                    references.find { |item| !item['image_url'].to_s.empty? } ||
                    base_image

        {
          'run_id' => sanitize_run_id(run_id),
          'updated_at' => data['updated_at'].to_s.empty? ? File.mtime(path).strftime('%Y-%m-%d %H:%M:%S') : data['updated_at'].to_s,
          'complete' => data['complete'] == true,
          'target_count' => target_count,
          'generated_count' => generated_count,
          'failed_count' => failed_count,
          'pending_count' => positive_int(data['pending_count'], 0),
          'base_image' => base_image,
          'references' => references,
          'results' => results,
          'plan' => data['plan'].is_a?(Hash) ? data['plan'] : {},
          'run_log_path' => path,
          'thumbnail_url' => thumbnail['image_url'].to_s.empty? ? thumbnail['url'].to_s : thumbnail['image_url'].to_s
        }
      rescue StandardError
        nil
      end

      def normalize_result_urls(item)
        data = item.dup
        path = data['image_path'].to_s.empty? ? data['path'].to_s : data['image_path'].to_s
        if !path.empty? && File.file?(path)
          url = file_url(path)
          data['url'] = url if data['url'].to_s.empty?
          data['image_url'] = url if data['image_url'].to_s.empty?
        end
        source = data['inspiration_source']
        data['inspiration_source'] = normalize_result_urls(source) if source.is_a?(Hash)
        data
      rescue StandardError
        item
      end

      def history_records
        path = history_path
        return orphan_history_records unless File.file?(path)

        data = JSON.parse(File.read(path, encoding: 'UTF-8'))
        records = data.is_a?(Array) ? data : []
        records = records.select { |record| record.is_a?(Hash) && File.file?(record['path'].to_s) }
        records = records.reject { |record| inspiration_history_action?(record['action']) }
        merge_orphan_history_records(records)
      rescue JSON::ParserError
        orphan_history_records
      end

      def write_history(records)
        FileUtils.mkdir_p(File.dirname(history_path))
        File.write(history_path, JSON.pretty_generate(records), encoding: 'UTF-8')
      end

      def merge_orphan_history_records(records)
        known = records.map { |record| safe_expand_path(record['path'].to_s) }.to_h { |path| [path, true] }
        merged = records + orphan_history_records.reject do |record|
          known[safe_expand_path(record['path'].to_s)]
        end
        merged.sort_by { |record| record['created_at'].to_s }.reverse.first(50)
      end

      def safe_expand_path(path)
        File.expand_path(path.to_s)
      rescue StandardError
        path.to_s
      end

      def orphan_history_records
        dir = File.join(output_root, 'history_images')
        return [] unless Dir.exist?(dir)

        patterns = %w[*.png *.jpg *.jpeg *.webp]
        patterns.flat_map { |pattern| Dir.glob(File.join(dir, pattern)) }.select { |path| File.file?(path) }.map do |path|
          stat = File.stat(path)
          name = File.basename(path)
          action = name.start_with?('inspiration_burst') ? 'inspiration_burst' : (name.start_with?('upscale') ? 'upscale' : 'render')
          next if inspiration_history_action?(action)

          {
            'id' => "recovered-#{stat.mtime.to_i}-#{name.hash.abs}",
            'created_at' => stat.mtime.strftime('%Y-%m-%d %H:%M:%S'),
            'action' => action,
            'mode' => Settings.read('request_mode'),
            'model' => Settings.read('model'),
            'prompt' => '',
            'source_path' => '',
            'path' => path,
            'url' => file_url(path),
            'recovered' => true
          }
        end.compact
      rescue StandardError
        []
      end

      def inspiration_history_action?(action)
        action.to_s == 'inspiration_burst'
      end

      def payload_values(payload, key)
        value = payload[key]
        value = payload[key.to_sym] if value.nil? && payload.respond_to?(:key?) && payload.key?(key.to_sym)
        Array(value).map(&:to_s).map(&:strip).reject(&:empty?)
      end

      def history_record_selected?(record, ids, paths)
        id = record['id'].to_s
        path = safe_expand_path(record['path'].to_s)
        ids.include?(id) || paths.map { |item| safe_expand_path(item) }.include?(path)
      end

      def sanitize_run_id(run_id)
        File.basename(run_id.to_s.strip, '.json').gsub(/[^A-Za-z0-9_.-]/, '')
      end

      def inspiration_file_paths(data)
        paths = []
        collect_image_path(paths, data['base_image'])
        Array(data['references']).each { |item| collect_image_path(paths, item) }
        Array(data['results']).each { |item| collect_image_path(paths, item) }
        paths.uniq
      end

      def collect_image_path(paths, item)
        return unless item.is_a?(Hash)

        %w[path image_path].each do |key|
          value = item[key].to_s
          paths << value unless value.empty?
        end
        collect_image_path(paths, item['history_record']) if item['history_record'].is_a?(Hash)
        collect_image_path(paths, item['inspiration_source']) if item['inspiration_source'].is_a?(Hash)
      end

      def safe_delete_output_file(path)
        return false unless output_file_path?(path)

        expanded = safe_expand_path(path)
        return false unless File.file?(expanded)

        File.delete(expanded)
        true
      rescue StandardError
        false
      end

      def output_file_path?(path)
        expanded = safe_expand_path(path).tr('\\', '/').downcase
        root = safe_expand_path(output_root).tr('\\', '/').downcase
        !expanded.empty? && expanded.start_with?("#{root}/")
      end

      def file_url_to_path(url)
        return nil unless url.to_s.start_with?('file:/')

        uri = URI(url)
        path = URI::DEFAULT_PARSER.unescape(uri.path.to_s)
        path = path.sub(%r{\A/([A-Za-z]:/)}, '\1')
        path.tr('/', File::SEPARATOR)
      rescue StandardError
        nil
      end

      def save_data_url_image(data_url, folder:, prefix:)
        header, encoded = data_url.split(',', 2)
        mime = header[/data:(.*?);base64/, 1] || 'image/png'
        ext = image_extension_from_mime(mime)
        dir = File.join(output_root, folder)
        FileUtils.mkdir_p(dir)
        path = File.join(dir, "#{prefix}-#{timestamp}.#{ext}")
        File.binwrite(path, Base64.decode64(encoded.to_s))
        path
      end

      def download_remote_image(url, folder:, prefix:, headers: {}, open_timeout: nil, read_timeout: nil)
        uri = URI(url)
        response = http_get_follow(uri, headers: headers, open_timeout: open_timeout, read_timeout: read_timeout)
        unless response.is_a?(Net::HTTPSuccess)
          raise "Image download failed: HTTP #{response.code} #{response.body.to_s[0, 300]}"
        end

        ext = image_extension_from_mime(response['content-type'].to_s)
        ext = File.extname(uri.path).sub('.', '') if ext == 'png' && !File.extname(uri.path).empty?
        dir = File.join(output_root, folder)
        FileUtils.mkdir_p(dir)
        path = File.join(dir, "#{prefix}-#{timestamp}.#{ext}")
        File.binwrite(path, response.body)
        path
      end

      def http_get_follow(uri, limit = 4, headers: {}, open_timeout: nil, read_timeout: nil)
        raise 'Too many redirects while downloading image.' if limit <= 0

        http = local_loopback_uri?(uri) ? Net::HTTP.new(uri.host, uri.port, nil) : Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.open_timeout = open_timeout || 15
        http.read_timeout = read_timeout || 120
        request = Net::HTTP::Get.new(uri)
        headers.each { |key, value| request[key] = value }
        response = http.request(request)
        if response.is_a?(Net::HTTPRedirection) && response['location']
          return http_get_follow(
            URI.join(uri, response['location']),
            limit - 1,
            headers: headers,
            open_timeout: open_timeout,
            read_timeout: read_timeout
          )
        end
        response
      end

      def local_loopback_uri?(uri)
        host = uri.host.to_s.downcase
        host == '127.0.0.1' || host == 'localhost' || host == '::1'
      end

      def image_extension_from_mime(mime)
        clean = mime.to_s.split(';').first
        case clean
        when 'image/jpeg', 'image/jpg'
          'jpg'
        when 'image/webp'
          'webp'
        else
          'png'
        end
      end

      def upscale_prompt
        '对这张图进行高清放大和细节增强，保持原始构图、建筑/室内/景观元素、材质关系和相机视角不变，提升清晰度、真实材质纹理、光影层次和照片级质感。'
      end

      def write_view_image(view, path, width, height, antialias: true)
        begin
          view.write_image(
            filename: path,
            width: width,
            height: height,
            antialias: antialias,
            transparent: false
          )
        rescue ArgumentError, TypeError
          view.write_image(path, width, height, antialias, 1.0)
        end
      end

      def activate_page(page)
        Sketchup.active_model.pages.selected_page = page
        Sketchup.active_model.active_view.refresh
      end

      def preserve_active_view
        model = Sketchup.active_model
        pages = model.pages
        original_page = pages.selected_page
        original_camera = model.active_view.camera
        yield
      ensure
        begin
          if original_page
            pages.selected_page = original_page
          elsif original_camera
            model.active_view.camera = original_camera
          end
          model.active_view.refresh
        rescue StandardError
          nil
        end
      end

      def install_ui
        return if @ui_installed

        command = UI::Command.new(EXTENSION_NAME) { show_dialog }
        command.tooltip = EXTENSION_NAME
        command.status_bar_text = 'Open the local AI render panel.'

        UI.menu('Extensions').add_item(command)
        toolbar = UI::Toolbar.new(EXTENSION_NAME)
        toolbar.add_item(command)
        toolbar.restore

        @ui_installed = true
      end
    end

    install_ui unless file_loaded?(__FILE__)
  end
end

file_loaded(__FILE__)
