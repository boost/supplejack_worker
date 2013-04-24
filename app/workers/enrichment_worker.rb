class EnrichmentWorker < AbstractWorker
  include Sidekiq::Worker

  attr_reader :parser, :parser_class
    
  def perform(enrichment_job_id)
    @enrichment_job_id = enrichment_job_id

    enrichment_job.start!
    setup_parser

    records.each do |record|
      break if stop_harvest?(enrichment_job)
      process_record(record)
    end

    while not api_update_finished?
      sleep(2)
    end

    enrichment_job.finish!
  end

  def enrichment_job
    @enrichment_job ||= EnrichmentJob.find(@enrichment_job_id)
  end

  def records
    Repository::Record.where("sources.source_id" => @parser_class.get_source_id)
  end

  def process_record(record)
    measure = Benchmark.measure do
      begin
        enrichment = enrichment_class.new(enrichment_job.enrichment, enrichment_options, record, @parser_class)
        enrichment.set_attribute_values
      unless enrichment.errors.any?
        post_to_api(enrichment) unless enrichment_job.test?
        enrichment_job.increment_records_count!
      else
        Rails.logger.info "Enrichment Errors: #{enrichment.errors.inspect}"
      end

      rescue RestClient::ResourceNotFound => e
        Rails.logger.info "Resource Not Found: #{enrichment.inspect}"
      rescue StandardError => e
        Rails.logger.info "\n#{e.message}, #{e.class.inspect}"
        e.backtrace.each {|b| Rails.logger.info b }
      end
    end
    puts "EnrichmentJob: PROCESS RECORD (#{measure.real.round(4)})" unless Rails.env.test?
  end

  private

  def api_update_finished?
    enrichment_job.reload
    enrichment_job.posted_records_count == enrichment_job.records_count
  end

  def setup_parser
    @parser = enrichment_job.parser
    @parser.load_file
    @parser_class = @parser.loader.parser_class
    @parser_class.environment = enrichment_job.environment
  end

  def enrichment_options
    @parser.enrichment_definitions[enrichment_job.enrichment.to_sym]
  end

  def enrichment_class
    klass = "HarvesterCore::#{enrichment_options[:type]}Enrichment"
    klass.constantize
  end

  def post_to_api(enrichment)
    record_id = enrichment.record.id
    attributes = enrichment.attributes

    ApiUpdateWorker.perform_async(record_id, attributes, enrichment_job.id)
  end

end