({
	generateJSON : function(cmp, event, helper) {
        var action = cmp.get("c.getRecord");
        action.setParams({ idRecord : cmp.get("v.id") });

        action.setCallback(this, function(response) {
            cmp.set("v.response", JSON.stringify(JSON.parse(response.getReturnValue()),null,2) );
               
        });
        $A.enqueueAction(action);
	},
    
    generateApex : function(cmp, event, helper) {
        var action = cmp.get("c.getSobjectToApex");
        action.setParams({ idRecord : cmp.get("v.id") });

        action.setCallback(this, function(response) {
            cmp.set("v.response", response.getReturnValue() );
               
        });
        $A.enqueueAction(action);
	}
})