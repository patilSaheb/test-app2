
require 'csv'

class AidtParser
  include Common
  def initialize()
    @customer_id = 1
    @account_id = "0"
  end

  def AccountId
    puts "#{@account_id}"
    if @account_id == "0"
      @account_id = Common.get_accountid(@customer_id)
    end

    @account_id
  end

  def parse_site
    @agent= Mechanize.new
    jobs_page = @agent.get "http://www.aidt.edu/jobs/"
    job_links = jobs_page.parser.xpath(".//*[@id='currentjobs']/tr/td[3]/a")

    #fields to scrape from external page
    job_city = jobs_page.parser.xpath(".//*[@id='currentjobs']/tr/td[2]/text()")

    job_title = jobs_page.parser.xpath(".//*[@id='currentjobs']/tr/td[3]/a/text()")

    from_date = jobs_page.parser.xpath(".//*[@id='currentjobs']/tr/td[4]/text()")

    to_date = jobs_page.parser.xpath(".//*[@id='currentjobs']/tr/td[5]/text()")

    job_note = jobs_page.parser.xpath("(//*[@id='currentjobs']/tr/td[6])/text()")

    company_name = jobs_page.parser.xpath(".//*[@id='currentjobs']/tr/td[1]/text()")

    Common.move_history(@customer_id)
    Common.destroy_jobs(@customer_id)

    index = 0
    job_links.each do |link|

      jobnote=job_note[index].to_s.strip

      # Ignore jobs that have a comment prefixed with *
      if jobnote.start_with?('*')
        index += 1
        next
      end

      get_job_url = link.attributes["href"].to_s
      get_job_url_page = @agent.get(get_job_url)
      puts "get_job_url_page : #{get_job_url_page.link_with(:xpath=>".//*[@id='content']/div[1]/figure/a")}"

      image_link = get_job_url_page.link_with(:xpath=>".//*[@id='content']/div[1]/figure/a")
         

      if image_link.blank? 
        puts "COULD NOT LOAD IMAGE FOR the job #{job_title[index]}"
        index +=1

        next
      end


      image_url = image_link.href.to_s

      image_url = "https://jobs.aidt.edu#{image_url}" if !image_url.include?("https")
 
      cmd = "convert #{image_url} -background white-flatten +matte destination_file_#{index}.tif"
      # puts "cmd = #{cmd}"

      ret = system(cmd)
      raise Exception.new("Error while running command #{cmd}") if !ret

      tesseract_cmd = "tesseract destination_file_#{index}.tif output_content"
      final_text = system(tesseract_cmd)

      puts "Tesseract Command : #{tesseract_cmd}. Status : #{final_text}"

      if final_text == true

        file = File.open("output_content.txt", "r")
        data = file.read
        file.close
        # if data.to_s.include?("'")
        #   data = data.gsub("'","")
        # end
        job_des = data.to_s
        job_url = image_url
        city = job_city[index].to_s
        state = ''
        if city.include?(",")
          loc = city.split(",")
          city = loc[0]
          state = loc[1]
        end


        # puts "to_date[index] = #{to_date[index]}"
        # puts "from_date[index] = #{from_date[index]}"
        # puts "job_note[index] = #{job_note[index]}"
        # # break
        my_job = Job.new
        # Job.insert_data(job_title[index],job_city[index],job_des,from_date[index],to_date[index],job_note[index],company_name[index],job_url)

        company = Sanitize.clean(company_name[index].to_s.strip)
        jobtitle = Sanitize.clean(job_title[index].to_s.strip)
        jobtitle = "#{jobtitle} - #{company}" if !(company.upcase.eql? "AIDT")
        jobtitle = jobtitle[0,128] if jobtitle.length > 128 
        
        puts "Company : #{company}"
        puts "company.upcase.eql? 'AIDT' = #{company.upcase.eql? 'AIDT'}"
        city = Sanitize.clean(city).strip
        state = Sanitize.clean(state).strip
        md5=Digest::MD5.new
        jobcode = md5.hexdigest("#{jobtitle}#{city}#{}")
        my_job.JobTitle = jobtitle
        my_job.City = city
        my_job.State = state
        my_job.Country   = "US" 
        my_job.ApplyUrl = Sanitize.clean(job_url.to_s.strip)
        my_job.FromDate   = DateTime.strptime(from_date[index], "%m/%d/%y") #DateTime.parse(from_date[index])
        my_job.ToDate = DateTime.strptime(to_date[index], "%m/%d/%y") #DateTime.parse(to_date[index])
        my_job.CompanyName = company
        # puts "Length before: #{job_des.length}"
        #my_job.JobDetail = Common.utf8(job_des.strip)#.force_encoding('iso-8859-1').encode('utf-8').delete!("^\u{0000}-\u{007F}")
        my_job.JobDetail = clean_data(job_des)
        # puts "Length After: #{my_job.JobDetail.length}"
        my_job.JobNote = jobnote
        my_job.JobCode = jobcode
        my_job.save!

        # break
      else
        puts "ERROR : Failed Command '#{tesseract_cmd}' "
      end

      index+=1
      #break
    end

    update_detail()

  end

  def clean_data(s)
    # puts "Before clean :#{s.length}"
    s = Common.utf8(s.strip)
    s = s.gsub(0xD2.chr, "")
    s = s.gsub(0xD3.chr, "")
    s = s.gsub(0xA8.chr, "")
    s = s.gsub(0xD5.chr, "'")
    s = s.gsub(0xDE.chr, "fi")
    s = s.gsub(0xD4.chr, "'")
    s = s.gsub(0xD1.chr, "-")

    # puts "After clean :#{s.length}"
    s
  end

  def update_detail()
    account_id = AccountId()
    update_sql = "UPDATE jobs SET JobDetail = REPLACE(JobDetail, '\\n', '<br />') WHERE AccountID = '#{account_id}';"

    res = ActiveRecord::Base.connection.execute(update_sql)
   
  end

  def ExportJobs
    account_id = AccountId()

    file_name = "#{Dir.home}/csv/#{account_id}_#{Date.today.strftime("%Y%m%d")}.csv"
    file = File.new(file_name, "w")
    file.close

    CSV.open(file_name, "wb") do |csv|
        csv << Job.column_names
        Job.where(AccountId: account_id).each do |job|
        csv << job.attributes.values
      end
    end

  end

  def MoveHistory
    Common.move_history(@customer_id)
  end
end