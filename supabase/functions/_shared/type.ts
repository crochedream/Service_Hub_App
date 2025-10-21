export interface ServiceAdminRegistration {
    email: string;
    password: string;
    firstName: string;
    lastName: string;
    phone: string;
    dateOfBirth?: string;
    gender?: string;
    addressLine?: string;
    city?: string;
    state?: string;
    postalCode?: string;
}
  
export interface CleaningServiceRegistration {
    businessName: string;
    businessLicense: string;
    businessAddress: string;
    description?: string;
    phone: string;
    email: string;
    logoUrl?: string;
}
  
export interface BranchAdminInvitation {
    email: string;
    phone?: string;
    branchId: string;
    permissions?: {
      canManageCleaners?: boolean;
      canManageBookings?: boolean;
      canViewReports?: boolean;
    };
}
  
export interface CleanerInvitation {
    email?: string;
    phone: string;
    branchId: string;
    employeeId?: string;
}