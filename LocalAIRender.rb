# frozen_string_literal: true

require 'sketchup.rb'
require 'extensions.rb'

module LLGHD
  module LocalAIRender
    EXTENSION_NAME = 'SU Local AI Render'
    EXTENSION_VERSION = '0.4.29'
    EXTENSION_ID = 'llghd.local_ai_render'

    loader = File.join(__dir__, 'LocalAIRender', 'core.rb')
    extension = SketchupExtension.new(EXTENSION_NAME, loader)
    extension.description = 'Capture SketchUp views and render them through a private AI image API with inspiration burst variants.'
    extension.version = EXTENSION_VERSION
    extension.creator = 'llghd'
    extension.copyright = "Copyright (c) #{Time.now.year} llghd"

    Sketchup.register_extension(extension, true)
  end
end
