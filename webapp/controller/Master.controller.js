sap.ui.define([
	"sap/ui/core/mvc/Controller"
], function(Controller) {
	"use strict";

	return Controller.extend("sap.ui.demo.wtnav.controller.Master", {
		onInit: function(oEvent) {

		},

		onPress: function(oEvent) {
			var fname = sap.ui.getCore().byId(this.createId("__input0")).getValue();
			this.getView().getModel("TempDataModel").setProperty("/", {
				"FirstName": fname
			});
			var oRouter = sap.ui.core.UIComponent.getRouterFor(this);
			oRouter.navTo("second");
		}

	});
});