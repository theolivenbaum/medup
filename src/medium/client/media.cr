# https://medium.com/media/e7722acf2886364130e03d2c7ad29de7
module Medium
  class Client
    module Media
      def media(id : String)
        puts "Fetching media" + id
        download("/media/" + id)
      end
    end
  end
end
