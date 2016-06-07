class SamsungParser
  include Common

  def initialize
    @customer_id = 2
    @curr_date = Common.get_sql_date()
    @account_id = "0"
  end


  def AccountId
    puts "#{@account_id}"
    if @account_id == "0"
      @account_id = Common.get_accountid(@customer_id)
    end

    @account_id
  end

  def scraper (jobs = 0)

    puts @curr_date
    acct_id = AccountId()
    browser = get_browser
    jobs_page = Nokogiri::HTML(browser.html)

    # Data from External Page
    total_jobs = jobs_page.xpath("//div[@class='title_h2']/h2/text()").to_s#.scan(/\d+/).last
    next_page_num=2
    @next_page_loop=11
    job_count = 0
# return

    while job_count<=total_jobs.to_i
      li_xpath =1
      jobs_page = Nokogiri::HTML(browser.html)
      ref_count = 0
      detail_links = jobs_page.xpath("//a[@class='title']")


      detail_links.each do |d_link|
        site_ids=d_link.attribute("siteid").text
        ref_codes=d_link.attribute("reqstnno").text.strip
        job_url="https://careers.us.samsung.com/careers/svc/app/viewJobDetail?reqstnNo=#{ref_codes}&siteId=#{site_ids}&compCd=C10"
        browser.link(:xpath,".//*[@id='content_career']/div[4]/div[2]/ul/li[#{li_xpath}]/div[1]/span[1]/a[2]").click
        sleep 3
        data_page = Nokogiri::HTML(browser.html)
        category = data_page.xpath("substring-before(.//*[@id='layer_jobdetail_scrollbar']/div[2]/div/div/div[2]/div[1]/div[1]/span[2],',')").to_s.strip
        job_type = data_page.xpath("substring-after(.//*[@id='layer_jobdetail_scrollbar']/div[2]/div/div/div[2]/div[1]/div[1]/span[2],',')").to_s.strip
        company_name = data_page.xpath(".//*[@id='layer_jobdetail_scrollbar']/div[2]/div/div/div[2]/div[1]/div[1]/div/strong/text()").to_s.strip
        job_city = data_page.xpath(".//*[@id='layer_jobdetail_scrollbar']/div[2]/div/div/div[2]/div[1]/div[1]/div/span[2]/text()").to_s.strip
        # job_title = data_page.xpath("//span[@class='title']/text()").to_s
        job_title = data_page.xpath("substring-before(//span[@class='title']/text(),'(')").to_s.strip
        job_detail = data_page.xpath(".//*[@id='layer_jobdetail_scrollbar']/div[2]/div/div/div[2]/div[2]").to_s
        start_date_s = data_page.xpath("//*[@id='layer_jobdetail_scrollbar']/div[2]/div/div/div[2]/div[1]/div[2]/div/div[2]/span/text()").to_s

        begin
           start_date = DateTime.parse(start_date_s).to_date.to_s
        rescue
          puts "INVALID DATE : #{start_date_s}. Putting current Date as default"
          start_date = DateTime.strptime(DateTime.now.to_s, '%Y-%m-%d').to_date.to_s
        end
        puts "start_date = #{start_date}"
      
        # job_req = data_page.xpath("//strong[contains(text(),'Necessary Skills / Attributes')]/following::div[1]/text()").to_s
        job_code = ref_codes
        #Job.insert_samsung_data(job_title,job_city,job_detail,company_name,job_url,category,job_type,job_req,job_code)


        my_job = Job.new
        my_job.JobTitle = job_title
        my_job.City = job_city
        my_job.Country   = "US" #Sanitize.clean(job_city[index])
        my_job.ApplyUrl = job_url
        my_job.CompanyName = company_name
        my_job.JobDetail = format_detail(job_detail)
        my_job.JobCode = job_code.to_s.strip
        my_job.JobType = job_type
        my_job.Category = Sanitize.clean(category.to_s)
        my_job.AccountId = @account_id #{}"AT-9900729756" 
        my_job.FromDate = start_date
        # my_job.JobRequirements = Common.utf8(job_req).strip
        # my_job.save!
        update_job(my_job)
        ref_count+=1
        begin
          browser.button(:title=>'close').click
          sleep 1
        rescue Exception => e
          puts "Clicking close failed. #{e.message}"
        end
        li_xpath+=1
        job_count+=1

        break if (jobs > 0 and job_count >= jobs)
      end

      break if (jobs > 0 and job_count >= jobs)

      # *** Navigate to Next Page ***
      #browser.link(:text,"#{next_page_num}").click
      nav_next_page(next_page_num, browser)
      # sleep 3
      break if !browser.exists?
      next_page_num+=1

    end

    update_detail()

    delete_oldresults()

  ensure
    browser.close if !browser.blank?

  end

  def format_detail(s)
    s = Common.utf8(s)
    s = s.strip
    # s = s.gsub("\n", "<br />")
    s
  end
 
  def update_detail()
    account_id = AccountId()
    update_sql = "UPDATE jobs SET JobDetail = REPLACE(JobDetail, '\\n', '<br />') WHERE AccountID = '#{account_id}';"

    res = ActiveRecord::Base.connection.execute(update_sql)
   
  end

  def delete_oldresults(date="")
    date = @curr_date if date.blank?

    account_id = AccountId()
    delete_sql = "DELETE from jobs where AccountID='#{account_id}' AND UpdateDate < '#{date}'"
    res = ActiveRecord::Base.connection.execute(delete_sql)
  end

  def update_job (the_job)
    account_id = AccountId()

    job = Job.find_by JobCode: the_job.JobCode,  AccountID: account_id
    if job.nil?
      puts"NEW"
      if !the_job.JobTitle.blank? and !the_job.JobDetail.blank? 
        the_job.save
      end
    else
      puts "Existing"

      job.JobTitle = the_job.JobTitle unless the_job.JobTitle.blank?
      job.City = the_job.City unless the_job.City.blank?
      job.Country   = "US" 
      job.ApplyUrl = the_job.ApplyUrl unless the_job.ApplyUrl.blank?
      job.CompanyName = the_job.CompanyName unless the_job.CompanyName.blank?
      job.JobDetail = the_job.JobDetail unless the_job.JobDetail.blank?
      job.JobType = the_job.JobType unless the_job.JobType.blank?
      job.Category = the_job.Category unless the_job.Category.blank?
      job.FromDate = the_job.FromDate unless the_job.FromDate.blank?
      job.UpdateDate = Time.now
      job.save
    end

  end

  def get_browser
   # headless = Headless.new(display: 100)
   # headless.start
    client = Selenium::WebDriver::Remote::Http::Default.new
    client.timeout = 180
    browser = Watir::Browser.new :firefox, :http_client => client
    browser.goto "https://careers.us.samsung.com/careers/svc/app/viewSearchJob?v_location=&company=AB11"
    browser
  end

  def nav_next_page(next_page_num,browser)
    if browser.link(:text,"#{next_page_num}").exists?
      puts "going to page #{next_page_num}"
      browser.link(:text,"#{next_page_num}").click
    elsif next_page_num % 10 == 1
      puts "going to next page"
      browser.link(:text,"Next").click
    else
      puts "#{next_page_num} does not exist.. Closing Browser"
      browser.close if !browser.blank?
    end
    sleep 5
    browser
  rescue =>e
    puts ("Error in nav_next_page(#{next_page_num}, '#{browser}')")
    browser.close if !browser.blank?
    return ""
  end


end
