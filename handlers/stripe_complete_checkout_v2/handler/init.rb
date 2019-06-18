# Require the dependencies file to load the vendor libraries
require File.expand_path(File.join(File.dirname(__FILE__), 'dependencies'))

class StripeCompleteCheckoutV2
  def initialize(input)
    # Set the input document attribute
    @input_document = REXML::Document.new(input)

    # Store the info values in a Hash of info names to values.
    @info_values = {}
    REXML::XPath.each(@input_document,"/handler/infos/info") { |item|
      @info_values[item.attributes['name']] = item.text
    }
    @enable_debug_logging = @info_values['enable_debug_logging'] == 'Yes'

    # Store parameters values in a Hash of parameter names to values.
    @parameters = {}
    REXML::XPath.match(@input_document, '/handler/parameters/parameter').each do |node|
      @parameters[node.attribute('name').value] = node.text.to_s
    end
  end

  def execute()
    # See your keys here https://dashboard.stripe.com/account
    Stripe.api_key = @info_values['stripe_api_secret']

    # Get the credit card details submitted by the form
    card = @parameters['card']
    currency = @parameters['currency']
    currency = 'usd' unless currency && currency.length > 0
    amount = @parameters['amount']
    description = @parameters['description']
    receipt_email = @parameters['receipt_email']

    puts "**Processing token: #{card} for #{amount} in #{currency}, email to: #{receipt_email} - #{description}" if @enable_debug_logging


    # Create the charge on Stripe's servers - this will charge the user's card
    begin
      success = false
      message = ""
      charge = Stripe::Charge.create(
      :amount => amount, # amount in cents, again
      :currency => currency,
      :card => card,
      :description => description,
      :receipt_email => receipt_email
      )
      success = true
      message = "Charge completed: id: #{charge.id}, amount: #{charge.amount}, captured: #{charge.captured}, paid: #{charge.paid}, last4: #{charge.card.last4}"
      puts message if @enable_debug_logging

    rescue Stripe::CardError => e
      message = "Card Declined: #{log_exception(e)}"
    rescue Stripe::InvalidRequestError => e
      message = "Invalid parameters were supplied to Stripe API: #{log_exception(e)}"
    rescue Stripe::AuthenticationError => e
      message = "Authentication with Stripe's API failed: #{log_exception(e)}"
    rescue Stripe::APIConnectionError => e
      message = "Network communication with Stripe failed: #{log_exception(e)}"
    rescue Stripe::StripeError => e
      message = "An unknown error occurred with the Stripe API: #{log_exception(e)}"
    end
      #Others should be raised to let the engine know there was a problem.



    <<-RESULTS
    <results>
      <result name="success">#{success}</result>
      <result name="charge_id">#{charge ? charge.id : nil}</result>
      <result name="message">#{message}</result>
    </results>
    RESULTS
  end

  # This is a template method that is used to escape results values (returned in
  # execute) that would cause the XML to be invalid.  This method is not
  # necessary if values do not contain character that have special meaning in
  # XML (&, ", <, and >), however it is a good practice to use it for all return
  # variable results in case the value could include one of those characters in
  # the future.  This method can be copied and reused between handlers.
  def escape(string)
    # Globally replace characters based on the ESCAPE_CHARACTERS constant
    string.to_s.gsub(/[&"><]/) { |special| ESCAPE_CHARACTERS[special] } if string
  end

  def log_exception(e)
    body = e.json_body
    err  = body[:error]
    message = <<-RESULTS

      ---------------------------------------
      There was an error processing a charge:
        Status is: #{e.http_status}
        Type is: #{err[:type]}
        Code is: #{err[:code]}
        Param is: #{err[:param]}
        Message is: #{err[:message]}
      ---------------------------------------
    RESULTS

    puts message if @enable_debug_logging
    message
  end

  # This is a ruby constant that is used by the escape method
  ESCAPE_CHARACTERS = {'&'=>'&amp;', '>'=>'&gt;', '<'=>'&lt;', '"' => '&quot;'}

end
