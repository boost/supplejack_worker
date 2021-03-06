# The Supplejack Worker code is Crown copyright (C) 2014, New Zealand Government, 
# and is licensed under the GNU General Public License, version 3. 
# See https://github.com/DigitalNZ/supplejack_worker for details. 
# 
# Supplejack was created by DigitalNZ at the National Library of NZ
# and the Department of Internal Affairs. http://digitalnz.org/supplejack

class Parser < ActiveResource::Base
  include ParserLoaderHelpers

  self.site = ENV['MANAGER_HOST']
  self.user = ENV['MANAGER_API_KEY']

  def last_harvested_at
    job = self.harvest_jobs.first
    job ? job.start_time : nil
  end

  def harvest_jobs
    HarvestJob.where(parser_id: self.id).desc(:start_time)
  end
end