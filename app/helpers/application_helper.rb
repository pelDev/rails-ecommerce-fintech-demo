module ApplicationHelper
    def payment_status_color(status)
        case status.to_s
            when "succeeded" then "bg-green-50 border-green-300 text-green-900"
            when "failed"    then "bg-red-50 border-red-300 text-red-900"
            when "processing" then "bg-blue-50 border-blue-300 text-blue-900"
            when "pending"   then "bg-yellow-50 border-yellow-300 text-yellow-900"
            else "bg-gray-50 border-gray-300 text-gray-900"
        end
    end
end
