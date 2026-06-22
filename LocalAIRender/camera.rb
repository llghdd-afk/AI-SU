# frozen_string_literal: true

require 'sketchup.rb'

module LLGHD
  module LocalAIRender
    module Camera
      module_function

      def snapshot
        model = Sketchup.active_model
        view = model.active_view
        from_camera(view.camera, model, view, selected_scene_name(model))
      end

      def from_camera(camera, model = Sketchup.active_model, view = model.active_view, scene_name = nil)
        {
          perspective: camera.perspective?,
          eye: point(camera.eye),
          target: point(camera.target),
          up: vector(camera.up),
          direction: vector(camera.direction),
          fov: safe_call(camera, :fov),
          focal_length: safe_call(camera, :focal_length),
          viewport: {
            width: safe_call(view, :vpwidth),
            height: safe_call(view, :vpheight)
          },
          aspect_ratio: aspect_ratio(view),
          scene: scene_name,
          axes: axes(model),
          units: units(model)
        }
      end

      def point(point)
        {
          x: point.x.to_f,
          y: point.y.to_f,
          z: point.z.to_f
        }
      end

      def vector(vector)
        {
          x: vector.x.to_f,
          y: vector.y.to_f,
          z: vector.z.to_f
        }
      end

      def aspect_ratio(view)
        width = safe_call(view, :vpwidth).to_f
        height = safe_call(view, :vpheight).to_f
        return nil if width <= 0 || height <= 0

        width / height
      end

      def selected_scene_name(model)
        page = model.pages.selected_page
        page ? page.name : nil
      rescue StandardError
        nil
      end

      def axes(model)
        axes = model.axes
        {
          origin: point(axes.origin),
          xaxis: vector(axes.xaxis),
          yaxis: vector(axes.yaxis),
          zaxis: vector(axes.zaxis)
        }
      rescue StandardError
        nil
      end

      def units(model)
        options = model.options['UnitsOptions']
        {
          length_unit: options['LengthUnit'],
          length_format: options['LengthFormat']
        }
      rescue StandardError
        nil
      end

      def safe_call(object, method_name)
        object.public_send(method_name)
      rescue StandardError
        nil
      end
    end
  end
end
