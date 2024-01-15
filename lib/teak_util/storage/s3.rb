# frozen_string_literal: true

require 'aws-sdk-s3'

module TeakUtil
  module Storage
    # Wraps access to S3 in a simpler key/value API.
    class S3
      # @param bucket [String] the name of the s3 bucket that this wrapper accesses
      # @param client [Aws::S3::Client] injectable S3 client for testing
      # @param prefix [String] prefix applied to all keys
      # @param server_side_encryption [String, nil] one of AES256 or aws:kms to
      #     encrypt written objects
      # @param kms_key_id [String, nil] if server_side_encryption is aws:ksm then this
      #   is the ARN of the KMS key to encrypt with. If blank, we will use the AWS managed
      #   aws/s3 KMS key
      # @param acl [String] the canned ACL to apply to objects, defaults to 'private'
      def initialize(bucket, client: nil, prefix: '', server_side_encryption: 'aws:kms',
                     kms_key_id: nil, acl: 'private')

        client ||= Aws::S3::Client.new
        @bucket = Aws::S3::Resource.new(client: client).bucket(bucket)
        @prefix = prefix

        @put_opts = {
          acl: acl,
          server_side_encryption: server_side_encryption
        }

        @put_opts[:ssekms_key_id] = kms_key_id if kms_key_id
      end

      # Set key to hold the string value. If a key already holds a value it
      # is overwritten.
      # @param key [String]
      # @param value [String, IO]
      # @param opts [Hash] Additional S3 options for the file
      # @option opts [String] :content_type A standard MIME type describing the format of the contents.
      # @option opts [String] :content_disposition Specifies presentational information for the object.
      def put(key, value, opts = {})
        path = "#{@prefix}#{key}"
        @bucket.object(path).put(
          opts.merge(@put_opts.merge(body: value))
        )
        path
      end

      # Retrieves the value stored at key
      # @param key [String]
      def get(key)
        path = "#{@prefix}#{key}"
        begin
          @bucket.object(path).get.body.read
        rescue Aws::S3::Errors::NoSuchKey
          return nil
        end
      end

      # Returns a URL which allows public access to the data stored at key
      # @param expires_in [Fixnum] number of seconds the link will remain valid for
      #   Maximum is 604800 (1 week).
      def public_url(key, expires_in: 1.week)
        path = "#{@prefix}#{key}"
        @bucket.object(path).presigned_url(:get, expires_in: expires_in.to_i)
      end
    end
  end
end
