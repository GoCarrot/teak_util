# frozen_string_literal: true

require 'teak_util/storage/s3'
require 'business_flow'
require 'mime-types'
require 'zip'
require 'zip/filesystem'

module TeakUtil
  module Storage
    # Creates a file and provides a time limited publicly accessible URL to the file.
    # The file may optionally be a Zip folder containing multiple distinct files. This
    # is achieved by passing in a hash for 'value', where the keys will be the contained
    # file names, and the values will be the file contents.
    class MakeExternallyAvailableFile
      include BusinessFlow::Base

      needs :storage, :key, :value
      wants(:compress) { false }

      lookup :storage, by: [:bucket_name, :prefix], with: -> { Storage::S3.new(bucket_name, prefix: "#{prefix}#{time_prefix}") }
      uses(:time_prefix) { Time.now.utc.strftime('%Y/%m/%d/') }

      provides :stored_file_name, :public_url, :full_path

      step :convert_data
      step :store_data

    private

      attr_accessor :data, :content_type

      def initialize
        @multiple_files = value.kind_of?(Hash)
        self.stored_file_name = compress ? "#{key}.zip" : key
        self.content_type = MIME::Types.type_for(stored_file_name).first&.to_s

        if multiple_files? && !compress
          errors.add(:compress, :invalid, message: 'must be true when storing multiple files')
        end
      end

      def multiple_files?
        @multiple_files
      end

      def convert_data
        self.data =
          if multiple_files?
            Zip::File.open_buffer(StringIO.new(String.new), create: true) do |zip_file|
              value.each do |(fname, contents)|
                zip_file.file.open(fname, +'w') do |file|
                  file.write(contents)
                end
              end
            end.string
          elsif compress
            Zip::File.open_buffer(StringIO.new(String.new), create: true) do |zip_file|
              zip_file.file.open(key, +'w') do |file|
                file.write(value)
              end
            end.string
          else
            value
          end
      end

      def store_data
        opts = {
          content_disposition: "attachment; filename=\"#{stored_file_name}\""
        }
        opts[:content_type] = content_type if content_type
        self.full_path = storage.put(stored_file_name, data, opts)

        self.public_url = storage.public_url(stored_file_name)
      end
    end
  end
end
