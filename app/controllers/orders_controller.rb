class OrdersController < ApplicationController
    before_action :authenticate_user!
    skip_before_action :authenticate_user!, only: [:new]

    def new
    end
end